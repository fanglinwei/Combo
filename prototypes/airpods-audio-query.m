// Read-only feasibility probe. No settings are changed and no identifiers are logged.
// Build/run instructions and upstream references: docs/airpods-audio-feasibility.md.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <IOBluetooth/IOBluetooth.h>
#include <dlfcn.h>
#include <assert.h>

static id Query(id object, NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return NSNull.null;
    @try { return [object valueForKey:key] ?: NSNull.null; }
    @catch (NSException *exception) { return NSNull.null; }
}

static id Battery(id value) {
    // A private getter's zero can mean a sleeping/unavailable component.
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NSNull.null;
    double number = [value doubleValue];
    return isfinite(number) && number == floor(number) && number > 0 && number <= 100 ? value : NSNull.null;
}

static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){ selector, scope, kAudioObjectPropertyElementMain };
}

static NSDictionary *Scalar(AudioObjectID device, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope, AudioObjectPropertyElement element, BOOL floating) {
    AudioObjectPropertyAddress address = Address(selector, scope);
    address.mElement = element;
    UInt32 value = 0, size = sizeof(value);
    OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value);
    Boolean settable = false;
    BOOL writable = AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable;
    id result = NSNull.null;
    if (status == noErr && size == sizeof(value)) {
        if (floating) {
            Float32 scalar;
            memcpy(&scalar, &value, sizeof(scalar));
            if (isfinite(scalar) && scalar >= 0 && scalar <= 1) result = @(scalar);
        } else result = @(value);
    }
    return @{ @"value": result, @"readStatus": @(status), @"settable": @(writable) };
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
            assert([Battery(@42) isEqual:@42]);
            for (id value in @[@0, @(-1), @101, @3.5, @(NAN), @YES, @"42", NSNull.null]) assert(Battery(value) == NSNull.null);
            assert(Query(NSObject.new, @"missingGetter") == NSNull.null);
            assert([Query(@42, @"stringValue") isEqual:@"42"]);
            puts("PASS: battery range/type/unknown handling and guarded getter");
            return 0;
        }
        if (argc != 1) { fputs("Usage: airpods-audio-query [--self-test]\n", stderr); return 2; }
        NSMutableDictionary *report = [@{ @"readOnly": @YES,
            @"os": NSProcessInfo.processInfo.operatingSystemVersionString } mutableCopy];
        AudioObjectPropertyAddress address = Address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
        AudioDeviceID device = 0;
        UInt32 size = sizeof(device);
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
        report[@"defaultOutputReadStatus"] = @(status);
        if (status == noErr && device != kAudioObjectUnknown) {
            report[@"volumeMain"] = Scalar(device, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 0, YES);
            report[@"volumeChannel1"] = Scalar(device, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1, YES);
            report[@"volumeChannel2"] = Scalar(device, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 2, YES);
            report[@"mute"] = Scalar(device, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, 0, NO);
            // ponytail: raw private HAL values only; add mappings after this OS build is verified.
            report[@"listeningModeHAL"] = Scalar(device, 'lstm', kAudioDevicePropertyScopeOutput, 0, NO);
            report[@"listeningModesHAL"] = Scalar(device, 'lsms', kAudioDevicePropertyScopeOutput, 0, NO);
        }
        NSMutableArray *batteries = NSMutableArray.array;
        for (IOBluetoothDevice *bluetooth in IOBluetoothDevice.pairedDevices) {
            if (!bluetooth.isConnected) continue;
            [batteries addObject:@{ @"left": Battery(Query(bluetooth, @"batteryPercentLeft")),
                @"right": Battery(Query(bluetooth, @"batteryPercentRight")),
                @"case": Battery(Query(bluetooth, @"batteryPercentCase")),
                @"single": Battery(Query(bluetooth, @"batteryPercentSingle")) }];
        }
        report[@"connectedBluetoothBatterySamples"] = batteries;
        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW | RTLD_LOCAL);
        dlopen("/System/Library/Frameworks/AVRouting.framework/AVRouting", RTLD_NOW | RTLD_LOCAL);
        id context = Query(NSClassFromString(@"AVOutputContext"), @"sharedSystemAudioContext");
        if (context == NSNull.null) context = Query(NSClassFromString(@"AVOutputContext"), @"sharedSystemAudio");
        // Let asynchronous route discovery deliver its initial state.
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        id output = Query(context, @"outputDevice");
        report[@"privateSystemContextAvailable"] = @(context != NSNull.null);
        report[@"privateCurrentOutputAvailable"] = @(output != NSNull.null);
        report[@"listeningMode"] = Query(output, @"currentBluetoothListeningMode");
        report[@"availableListeningModes"] = Query(output, @"availableBluetoothListeningModes");
        report[@"supportsConversationAwareness"] = Query(output, @"supportsConversationDetection");
        report[@"conversationAwareness"] = Query(output, @"isConversationDetectionEnabled");
        report[@"modeSetterPresent"] = @([output respondsToSelector:NSSelectorFromString(@"setCurrentBluetoothListeningMode:error:")]);
        report[@"conversationSetterPresent"] = @([output respondsToSelector:NSSelectorFromString(@"setConversationDetectionEnabled:error:")]);
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) { fputs("Cannot serialize audio report\n", stderr); return 1; }
        [[NSFileHandle fileHandleWithStandardOutput] writeData:json];
        puts("");
    }
    return 0;
}
