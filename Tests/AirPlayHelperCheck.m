#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include <assert.h>
#include <stdio.h>
#include <unistd.h>

@interface TestAudioContext : NSObject
@property (nonatomic, strong) id outputDevice;
@property (nonatomic, strong) id outputDevices;
@property (nonatomic, strong) NSString *associatedAudioDeviceID;
+ (id)sharedSystemAudioContext;
@end
static TestAudioContext *testRouteContext;
@implementation TestAudioContext
+ (id)sharedSystemAudioContext { return testRouteContext; }
@end

@interface TestRouteEndpoint : NSObject
@property (nonatomic, strong) NSString *deviceID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *modelID;
@property (nonatomic, strong) NSNumber *canSetVolume;
@end
@implementation TestRouteEndpoint
@end

// HAL object IDs belong to each process; the same UID is 86 in this helper and 144 in its caller.
static NSUInteger defaultReads;
static BOOL changeRouteDuringRead;
static OSStatus TestGetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                    UInt32 qualifierSize, const void *qualifier, UInt32 *size, void *data) {
    if (object == kAudioObjectSystemObject && address->mSelector == kAudioHardwarePropertyDefaultOutputDevice) {
        *(AudioDeviceID *)data = changeRouteDuringRead && ++defaultReads > 2 ? 87 : 86;
        *size = sizeof(AudioDeviceID); return noErr;
    }
    if (object == kAudioObjectSystemObject && address->mSelector == kAudioHardwarePropertyTranslateUIDToDevice
        && qualifierSize == sizeof(CFStringRef) && qualifier && CFEqual(*(CFStringRef *)qualifier, CFSTR("test-route-uid"))) {
        *(AudioDeviceID *)data = 86; *size = sizeof(AudioDeviceID); return noErr;
    }
    if (object == 86 && address->mSelector == kAudioDevicePropertyDeviceUID) {
        *(CFStringRef *)data = CFRetain(CFSTR("test-route-uid")); *size = sizeof(CFStringRef); return noErr;
    }
    if (object == 86 && address->mSelector == kAudioDevicePropertyTransportType) {
        *(UInt32 *)data = kAudioDeviceTransportTypeAirPlay; *size = sizeof(UInt32); return noErr;
    }
    return kAudioHardwareUnknownPropertyError;
}
static Class TestClassFromString(NSString *name) {
    return [name isEqual:@"AVOutputContext"] ? TestAudioContext.class : NSClassFromString(name);
}
#define AudioObjectGetPropertyData TestGetPropertyData
#define NSClassFromString TestClassFromString
#define main ComboAirPodsHelperMain
#import "../Combo/Audio/AirPodsHelper.m"
#undef main
#undef NSClassFromString
#undef AudioObjectGetPropertyData

static NSDictionary *ReadRoute(const char *deviceID, NSString *token, int *status) {
    FILE *capture = tmpfile(); assert(capture);
    int saved = dup(STDOUT_FILENO); assert(saved >= 0);
    assert(dup2(fileno(capture), STDOUT_FILENO) >= 0);
    defaultReads = 0;
    const char *arguments[] = {"helper", "--route", deviceID, token.UTF8String};
    *status = ComboAirPodsHelperMain(4, arguments);
    fflush(stdout);
    assert(dup2(saved, STDOUT_FILENO) >= 0); close(saved);
    fseek(capture, 0, SEEK_SET);
    NSData *data = [[[NSFileHandle alloc] initWithFileDescriptor:fileno(capture) closeOnDealloc:NO] readDataToEndOfFile];
    fclose(capture);
    return data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

int main(void) { @autoreleasepool {
    TestAudioContext *context = TestAudioContext.new;
    NSObject *one = NSObject.new, *two = NSObject.new;
    assert(RouteEndpoint(nil) == nil && RouteEndpoint(context) == nil);
    context.outputDevice = one;
    assert(RouteEndpoint(context) == one);
    context.outputDevices = @[one, two];
    assert(RouteEndpoint(context) == nil); // A primary endpoint cannot identify a multiroom route.
    context.outputDevices = @[one];
    context.outputDevice = nil;
    assert(RouteEndpoint(context) == one);
    context.outputDevices = @[];
    assert(RouteEndpoint(context) == nil);
    context.outputDevices = @"invalid";
    assert(RouteEndpoint(context) == nil);
    assert(BoolValue(nil) == NSNull.null && BoolValue(@1) == NSNull.null);
    assert([BoolValue(@NO) isEqual:@NO] && [BoolValue(@YES) isEqual:@YES]);
    testRouteContext = TestAudioContext.new;
    testRouteContext.associatedAudioDeviceID = @"test-route-uid";
    TestRouteEndpoint *endpoint = TestRouteEndpoint.new;
    endpoint.deviceID = @"living-room"; endpoint.name = @"客厅"; endpoint.modelID = @"AppleTV14,1"; endpoint.canSetVolume = @NO;
    testRouteContext.outputDevice = endpoint;
    testRouteContext.outputDevices = @[endpoint];
    int status = 0;
    NSString *token = @"b75d79c3014dbd24bff7bfd667ff96e4cb10b645facfb5c405348d49f57e27c7";
    NSDictionary *reply = ReadRoute("144", token, &status);
    assert(status == 0 && [reply[@"name"] isEqual:@"客厅"] && [reply[@"deviceID"] isEqual:@144]);
    assert([reply[@"target"] isEqual:token]);
    ReadRoute("144", [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0], &status);
    assert(status == 1); // The UID remains the authority, never the numeric ID alone.
    for (NSString *invalid in @[@"0", @"-1", @"144x", @"4294967296"]) {
        ReadRoute(invalid.UTF8String, token, &status); assert(status == 1);
    }
    changeRouteDuringRead = YES;
    ReadRoute("144", token, &status); assert(status == 1);
    changeRouteDuringRead = NO;
    puts("PASS: AirPlay helper process-local IDs, UID matching, stale routes, single endpoints and unknown volume capability");
    return 0;
} }
