// Read-only private API feasibility probe, verified on macOS 27.0 (26A428).
// Build: xcrun clang -fobjc-arc -framework Foundation prototypes/personal-hotspot-query.m -o /tmp/combo-hotspot-query
// Check: /tmp/combo-hotspot-query --self-test
// Discover for 10 seconds: /tmp/combo-hotspot-query
// ponytail: one verified OS build only; re-check the private ABI before widening support.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <string.h>
static NSDictionary *Snapshot(id device) {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"deviceName", @"batteryLife", @"signalStrength", @"networkType", @"cachedDevice", @"lastSeen"]) {
        if (![device respondsToSelector:NSSelectorFromString(key)]) continue;
        id value = [device valueForKey:key];
        Class type = [key isEqualToString:@"deviceName"] ? NSString.class : NSNumber.class;
        if ([value isKindOfClass:type]) row[key] = value;
    }
    return row;
}
@interface SampleDevice : NSObject
@property id deviceName, batteryLife, signalStrength, networkType;
@end
@implementation SampleDevice
@end
static int SelfTest(void) {
    SampleDevice *sample = [SampleDevice new];
    sample.deviceName = @"Test phone";
    sample.batteryLife = @75;
    sample.signalStrength = @4;
    sample.networkType = @8;
    NSDictionary *expected = @{@"deviceName": @"Test phone", @"batteryLife": @75, @"signalStrength": @4, @"networkType": @8};
    if (![Snapshot(sample) isEqual:expected]) return 1;
    sample.batteryLife = @"invalid";
    sample.signalStrength = nil;
    if (Snapshot(sample)[@"batteryLife"] || Snapshot(sample)[@"signalStrength"]) return 1;
    if (Snapshot([NSObject new]).count) return 1;
    puts("PASS: available fields preserved, absent and malformed fields omitted; raw network type unchanged.");
    return 0;
}
@interface HotspotProbe : NSObject
@property NSUInteger callbacks;
@property NSUInteger devices;
@end
@implementation HotspotProbe
- (void)session:(id)session updatedFoundDevices:(NSArray *)devices {
    self.callbacks++; self.devices = devices.count;
    NSMutableArray *rows = [NSMutableArray array];
    for (id device in devices) {
        NSDictionary *row = Snapshot(device);
        [rows addObject:row];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"callback": @(self.callbacks), @"devices": rows} options:0 error:nil];
    puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String); fflush(stdout);
}
@end
int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return SelfTest();
    if (argc != 1) { fputs("Usage: personal-hotspot-query [--self-test]\n", stderr); return 1; }
    if (![[NSProcessInfo processInfo].operatingSystemVersionString containsString:@"26A428"]) {
        fputs("Unsupported build: re-verify the private ABI before running.\n", stderr); return 2;
    }
    void *framework = dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY);
    Class cls = NSClassFromString(@"SFRemoteHotspotSession");
    if (!framework || !cls) { puts("UNAVAILABLE: framework/class missing"); return 2; }
    id session = [[cls alloc] init];
    for (NSString *name in @[@"setDelegate:", @"startBrowsing", @"stopBrowsing"]) {
        if (![session respondsToSelector:NSSelectorFromString(name)]) { puts("UNAVAILABLE: selector missing"); return 2; }
    }
    HotspotProbe *probe = [HotspotProbe new];
    ((void (*)(id, SEL, id))objc_msgSend)(session, NSSelectorFromString(@"setDelegate:"), probe);
    puts("Starting 10-second discovery; no enable/connect selectors are invoked."); fflush(stdout);
    ((void (*)(id, SEL))objc_msgSend)(session, NSSelectorFromString(@"startBrowsing"));
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    ((void (*)(id, SEL))objc_msgSend)(session, NSSelectorFromString(@"stopBrowsing"));
    printf("Finished: callbacks=%lu, lastDeviceCount=%lu\n", (unsigned long)probe.callbacks, (unsigned long)probe.devices);
    return probe.callbacks ? 0 : 3;
} }
