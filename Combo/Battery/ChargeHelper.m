// Short-lived, unprivileged PowerUI client. Only --charge may mutate state.
#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/IOKitLib.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL matches(Class cls, NSString *name, const char *result, const char *argument) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char *r = method_copyReturnType(method), *a = method_copyArgumentType(method, 2);
    BOOL valid = r && a && !strcmp(r, result) && !strcmp(a, argument);
    free(r); free(a);
    return valid;
}

static void readBattery(NSMutableDictionary *reply) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info) {
        NSArray *sources = CFBridgingRelease(IOPSCopyPowerSourcesList(info));
        for (id source in sources) {
            NSDictionary *d = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, (__bridge CFTypeRef)source);
            if (![d[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) continue;
            NSString *power = d[@kIOPSPowerSourceStateKey];
            if ([power isEqual:@kIOPSACPowerValue]) reply[@"onAC"] = @YES;
            else if ([power isEqual:@kIOPSBatteryPowerValue]) reply[@"onAC"] = @NO;
            if ([d[@kIOPSIsChargingKey] isKindOfClass:NSNumber.class]) reply[@"charging"] = d[@kIOPSIsChargingKey];
            NSNumber *current = d[@kIOPSCurrentCapacityKey], *maximum = d[@kIOPSMaxCapacityKey];
            if ([current isKindOfClass:NSNumber.class] && [maximum isKindOfClass:NSNumber.class] && maximum.doubleValue > 0)
                reply[@"percent"] = @(100 * current.doubleValue / maximum.doubleValue);
            break;
        }
        CFRelease(info);
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (service) {
        id data = CFBridgingRelease(IORegistryEntryCreateCFProperty(service, CFSTR("ChargerData"), kCFAllocatorDefault, 0));
        if ([data isKindOfClass:NSDictionary.class] && [data[@"NotChargingReason"] isKindOfClass:NSNumber.class])
            reply[@"limitBlocked"] = ([data[@"NotChargingReason"] unsignedLongLongValue] & 0x1000000) ? @YES : @NO;
        IOObjectRelease(service);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL request = argc == 3 && !strcmp(argv[1], "--charge");
        BOOL status = argc == 2 && !strcmp(argv[1], "--status");
        if (!request && !status) return 2;
        char *end = NULL;
        long expectedLimit = request ? strtol(argv[2], &end, 10) : 0;
        if (request && (!argv[2][0] || *end || expectedLimit < 1 || expectedLimit >= 100)) return 2;
        NSMutableDictionary *reply = [@{@"supported": @NO, @"accepted": @NO, @"attempted": @NO} mutableCopy];
        @try {
            if (![[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"] load]) @throw [NSException exceptionWithName:@"unsupported" reason:nil userInfo:nil];
            Class cls = NSClassFromString(@"PowerUISmartChargeClient");
            if (!matches(cls, @"initWithClientName:", "@", "@") ||
                !matches(cls, @"isMCLCurrentlyEnabled:", @encode(NSUInteger), "^@") ||
                !matches(cls, @"getMCLLimitWithError:", @encode(unsigned char), "^@") ||
                !matches(cls, @"temporarilyDisableMCL:", @encode(BOOL), "^@"))
                @throw [NSException exceptionWithName:@"unsupported" reason:nil userInfo:nil];
            id client = ((id (*)(id, SEL, NSString *))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithClientName:"), @"ComboChargeHelper");
            if (!client) @throw [NSException exceptionWithName:@"unavailable" reason:nil userInfo:nil];
            NSError *error = nil;
            NSUInteger state = ((NSUInteger (*)(id, SEL, NSError **))objc_msgSend)(client, NSSelectorFromString(@"isMCLCurrentlyEnabled:"), &error);
            if (error) @throw [NSException exceptionWithName:@"read_failed" reason:nil userInfo:nil];
            unsigned char limit = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, NSSelectorFromString(@"getMCLLimitWithError:"), &error);
            if (error) @throw [NSException exceptionWithName:@"read_failed" reason:nil userInfo:nil];
            reply[@"supported"] = @YES; reply[@"manualState"] = @(state); reply[@"limit"] = @(limit);
            readBattery(reply);
            if (request) {
                // State 1 and bit 24 are observed private values; unknown states fail closed.
                BOOL eligible = state == 1 && limit == expectedLimit &&
                    [reply[@"onAC"] isEqual:@YES] && [reply[@"charging"] isEqual:@NO] &&
                    [reply[@"limitBlocked"] isEqual:@YES] && reply[@"percent"] &&
                    [reply[@"percent"] doubleValue] >= 0 && [reply[@"percent"] doubleValue] < 100;
                if (!eligible) reply[@"error"] = @"not_eligible";
                else {
                    reply[@"attempted"] = @YES;
                    BOOL accepted = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(client, NSSelectorFromString(@"temporarilyDisableMCL:"), &error);
                    reply[@"accepted"] = accepted && error == nil ? @YES : @NO;
                    if (!accepted || error) reply[@"error"] = @"request_failed";
                }
            }
        } @catch (NSException *exception) {
            reply[@"error"] = exception.name;
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
        if (!data) return 3;
        fwrite(data.bytes, 1, data.length, stdout); putchar('\n');
    }
    return 0;
}
