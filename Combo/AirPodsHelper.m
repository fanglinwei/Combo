#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <IOBluetooth/IOBluetooth.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>

// Private selectors verified on macOS 27 (26A428); keep failures inside this helper.
@protocol AirPodsEndpoint
- (BOOL)setCurrentBluetoothListeningMode:(NSString *)mode error:(NSError **)error;
- (BOOL)setConversationDetectionEnabled:(BOOL)enabled error:(NSError **)error;
@end

static id Value(id object, NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}
static id Percent(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NSNull.null;
    double n = [value doubleValue];
    return isfinite(n) && n == floor(n) && n > 0 && n <= 100 ? value : NSNull.null;
}
static id BoolValue(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ? value : NSNull.null;
}
static AudioDeviceID DefaultOutput(void) {
    AudioDeviceID device = 0; UInt32 size = sizeof(device);
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, 0};
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &device) == noErr ? device : 0;
}
static NSString *DeviceToken(AudioDeviceID device) {
    CFStringRef uid = NULL; UInt32 size = sizeof(uid);
    AudioObjectPropertyAddress a = {kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal, 0};
    if (!device || AudioObjectGetPropertyData(device, &a, 0, NULL, &size, &uid) != noErr || !uid) return nil;
    NSData *bytes = [(__bridge_transfer NSString *)uid dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *token = NSMutableString.string;
    for (NSUInteger i = 0; i < sizeof(digest); i++) [token appendFormat:@"%02x", digest[i]];
    return token;
}
static BOOL ContextMatches(id context, AudioDeviceID device) {
    id uid = Value(context, @"associatedAudioDeviceID");
    if (![uid isKindOfClass:NSString.class]) return NO;
    CFStringRef qualifier = (__bridge CFStringRef)uid;
    AudioDeviceID mapped = 0; UInt32 size = sizeof(mapped);
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal, 0};
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof(qualifier), &qualifier, &size, &mapped) == noErr && mapped == device && device != 0;
}
static BOOL Stable(id context, AudioDeviceID device, NSString *token, NSString *endpointID) {
    id output = Value(context, @"outputDevice");
    return DefaultOutput() == device && [DeviceToken(device) isEqual:token] && ContextMatches(context, device)
        && endpointID.length && [Value(output, @"deviceID") isEqual:endpointID];
}
static NSDictionary *Modes(void) {
    return @{@"off": @"AVOutputDeviceBluetoothListeningModeNormal",
             @"transparency": @"AVOutputDeviceBluetoothListeningModeAudioTransparency",
             @"adaptive": @"AVOutputDeviceBluetoothListeningModeAutomatic",
             @"noise-cancellation": @"AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation"};
}
static NSString *Mode(id output) {
    id raw = Value(output, @"currentBluetoothListeningMode");
    for (NSString *key in Modes()) if ([Modes()[key] isEqual:raw]) return key;
    return nil;
}
static NSArray *AvailableModes(id output) {
    id raw = Value(output, @"availableBluetoothListeningModes");
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *modes = NSMutableArray.array;
    for (NSString *key in @[@"transparency", @"adaptive", @"noise-cancellation", @"off"])
        if ([raw containsObject:Modes()[key]]) [modes addObject:key];
    return modes;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        BOOL writing = argc == 5 && (!strcmp(argv[1], "--mode") || !strcmp(argv[1], "--conversation"));
        if (!writing && !(argc == 1 || (argc == 2 && !strcmp(argv[1], "--status")))) return 2;
        NSString *command = writing ? @(argv[1]) : @"--status";
        NSString *requested = writing ? @(argv[2]) : nil;
        if (([command isEqual:@"--mode"] && !Modes()[requested]) ||
            ([command isEqual:@"--conversation"] && ![@[@"on", @"off"] containsObject:requested])) return 2;
        AudioDeviceID device = DefaultOutput();
        NSString *token = DeviceToken(device);
        NSMutableDictionary *reply = [@{@"deviceID": @(device), @"target": token ?: @"", @"available": @NO,
            @"modes": @[], @"canSetMode": @NO, @"canSetConversation": @NO,
            @"attempted": @NO, @"verified": @NO} mutableCopy];
        IOBluetoothDevice *bluetooth = nil;
        for (IOBluetoothDevice *candidate in IOBluetoothDevice.pairedDevices) {
            id mapped = Value(candidate, @"outputAudioDeviceID");
            if (candidate.isConnected && [mapped isKindOfClass:NSNumber.class] && [mapped unsignedIntValue] == device && device) {
                if (bluetooth) { bluetooth = nil; break; }
                bluetooth = candidate;
            }
        }
        if (bluetooth && token) {
            reply[@"available"] = @YES;
            reply[@"left"] = Percent(Value(bluetooth, @"batteryPercentLeft"));
            reply[@"right"] = Percent(Value(bluetooth, @"batteryPercentRight"));
            reply[@"caseBattery"] = Percent(Value(bluetooth, @"batteryPercentCase"));
            reply[@"single"] = Percent(Value(bluetooth, @"batteryPercentSingle"));
        }
        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW | RTLD_LOCAL);
        dlopen("/System/Library/Frameworks/AVRouting.framework/AVRouting", RTLD_NOW | RTLD_LOCAL);
        id context = Value(NSClassFromString(@"AVOutputContext"), @"sharedSystemAudioContext")
            ?: Value(NSClassFromString(@"AVOutputContext"), @"sharedSystemAudio");
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        id output = Value(context, @"outputDevice");
        id identifier = Value(output, @"deviceID");
        NSString *endpointID = [identifier isKindOfClass:NSString.class] ? identifier : nil;
        BOOL matched = bluetooth && Stable(context, device, token, endpointID);
        BOOL supportsCA = [BoolValue(Value(output, @"supportsConversationDetection")) isEqual:@YES];
        BOOL canMode = matched && AvailableModes(output).count > 0 && [output respondsToSelector:@selector(setCurrentBluetoothListeningMode:error:)];
        BOOL canCA = matched && supportsCA && BoolValue(Value(output, @"isConversationDetectionEnabled")) != NSNull.null
            && [output respondsToSelector:@selector(setConversationDetectionEnabled:error:)];
        if (writing) {
            // UI passes both its observed object ID and a UID hash; refuse stale clicks.
            NSString *expectedDevice = @(argv[3]);
            BOOL sameTarget = [expectedDevice isEqual:[@(device) stringValue]] && [token isEqual:@(argv[4])];
            BOOL modeCommand = [command isEqual:@"--mode"];
            BOOL allowed = modeCommand ? canMode && [AvailableModes(output) containsObject:requested] : canCA;
            if (!sameTarget || !matched) reply[@"error"] = @"device_changed";
            else if (!allowed) reply[@"error"] = @"unsupported";
            else {
                NSError *error = nil;
                reply[@"attempted"] = @YES;
                BOOL accepted = modeCommand
                    ? [(id<AirPodsEndpoint>)output setCurrentBluetoothListeningMode:Modes()[requested] error:&error]
                    : [(id<AirPodsEndpoint>)output setConversationDetectionEnabled:[requested isEqual:@"on"] error:&error];
                BOOL verified = NO;
                // Observe for 1.5 s, including Off which firmware can silently reject.
                for (int i = 0; i < 15; i++) {
                    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    if (!Stable(context, device, token, endpointID)) { reply[@"error"] = @"device_changed"; break; }
                    output = Value(context, @"outputDevice");
                    verified = modeCommand ? [Mode(output) isEqual:requested]
                        : [BoolValue(Value(output, @"isConversationDetectionEnabled")) isEqual:@([requested isEqual:@"on"])];
                }
                reply[@"verified"] = accepted && verified && error == nil && !reply[@"error"] ? @YES : @NO;
                if (![reply[@"verified"] boolValue] && !reply[@"error"]) reply[@"error"] = @"unconfirmed";
            }
        }
        if (matched && Stable(context, device, token, endpointID)) {
            output = Value(context, @"outputDevice");
            reply[@"mode"] = Mode(output) ?: NSNull.null;
            reply[@"modes"] = AvailableModes(output);
            reply[@"canSetMode"] = @(canMode);
            reply[@"conversation"] = supportsCA ? BoolValue(Value(output, @"isConversationDetectionEnabled")) : NSNull.null;
            reply[@"canSetConversation"] = @(canCA);
        } else if (writing && !reply[@"error"]) reply[@"error"] = @"device_changed";
        if (DefaultOutput() != device || ![DeviceToken(device) isEqual:token]) {
            reply[@"available"] = @NO; reply[@"canSetMode"] = @NO; reply[@"canSetConversation"] = @NO;
            reply[@"error"] = @"device_changed";
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
        if (!data || data.length > 8192) return 1;
        [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
        return 0;
    } @catch (NSException *exception) { return 1; } }
}
