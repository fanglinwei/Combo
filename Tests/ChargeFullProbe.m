// Standalone probe; never linked into Combo. Default invocation only reads.
// Build: xcrun clang -fobjc-arc -framework Foundation Tests/ChargeFullProbe.m -o build/charge-full-probe
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL boolCall(id client, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([client class], selector);
    if (!method) { printf("%s: unavailable\n", name.UTF8String); return NO; }
    // Do not guess ABI after an OS change.
    char *returnType = method_copyReturnType(method);
    char *argumentType = method_copyArgumentType(method, 2);
    BOOL wide = !strcmp(returnType, @encode(NSUInteger)) && ([name hasPrefix:@"is"] || [name isEqualToString:@"getMCLLimitWithError:"]);
    BOOL byte = !strcmp(returnType, @encode(unsigned char)) && [name isEqualToString:@"getMCLLimitWithError:"];
    BOOL valid = method_getNumberOfArguments(method) == 3 &&
        (!strcmp(returnType, @encode(BOOL)) || wide || byte) && !strcmp(argumentType, "^@");
    printf("%s ABI: %s\n", name.UTF8String, method_getTypeEncoding(method));
    free(returnType); free(argumentType);
    if (!valid) { printf("Unsupported ABI; skipped\n"); return NO; }
    NSError *error = nil;
    NSUInteger value = wide ? ((NSUInteger (*)(id, SEL, NSError **))objc_msgSend)(client, selector, &error)
                            : byte ? ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, selector, &error)
                            : ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(client, selector, &error);
    printf("%s: value=%lu error=%s\n", name.UTF8String, (unsigned long)value, error ? error.description.UTF8String : "none");
    return value == 1 && error == nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        BOOL requestCharge = argc == 2 && !strcmp(argv[1], "--temporary-charge");
        BOOL requestMCL = argc == 2 && !strcmp(argv[1], "--temporary-mcl");
        if (argc > 1 && !requestCharge && !requestMCL) { fprintf(stderr, "Usage: charge-full-probe [--temporary-charge | --temporary-mcl]\n"); return 2; }
        if (![[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"] load]) return 3;
        Class cls = NSClassFromString(@"PowerUISmartChargeClient");
        SEL init = NSSelectorFromString(@"initWithClientName:");
        if (!cls || ![cls instancesRespondToSelector:init]) return 4;
        @try {
            id client = ((id (*)(id, SEL, NSString *))objc_msgSend)([cls alloc], init, @"ComboChargeFeasibilityProbe");
            if (!client) return 5;
            BOOL manualLimit = boolCall(client, @"isMCLCurrentlyEnabled:");
            boolCall(client, @"isSmartChargingCurrentlyEnabled:");
            boolCall(client, @"getMCLLimitWithError:");
            if (requestCharge || requestMCL) {
                // Only the temporary operation: never disable MCL or rewrite its saved value.
                if (!manualLimit) { printf("Manual charge limit not confirmed; refusing mutation.\n"); return 6; }
                return boolCall(client, requestMCL ? @"temporarilyDisableMCL:" : @"temporarilyEnableCharging:") ? 0 : 7;
            }
        } @catch (NSException *exception) {
            fprintf(stderr, "%s\n", exception.description.UTF8String); return 8;
        }
    }
    return 0;
}
