// Read-only feasibility probe; NOT the final battery-menu app list.
// ABI and defaults verified from ControlCenter on macOS 27.0 (26A428).
// Build: clang -fobjc-arc -framework Foundation prototypes/system-energy-query.m -o /tmp/combo-system-energy-query
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

int main(void) {
    @autoreleasepool {
        if (![[NSProcessInfo processInfo].operatingSystemVersionString containsString:@"26A428"]) {
            fputs("Unsupported build: re-verify the private ABI before running.\n", stderr);
            return 1;
        }
        void *library = dlopen("/usr/lib/libsystemstats.dylib", RTLD_NOW | RTLD_LOCAL);
        if (!library) { fprintf(stderr, "%s\n", dlerror()); return 2; }
        // x0=120, x1=5, d0=120*500 in the observed arm64e call site.
        // The exact semantic meaning of the second argument is not established.
        typedef NSDictionary *(*Query)(uint64_t, uint64_t, double);
        Query query = (Query)dlsym(library, "systemstats_get_top_coalitions");
        if (!query) { fputs("Missing systemstats symbol.\n", stderr); return 3; }
        // Bound a synchronous XPC stall in this standalone probe.
        alarm(15);
        NSDictionary *result = query(120, 5, 60000.0);
        alarm(0);
        if (![result isKindOfClass:NSDictionary.class]) {
            fputs("Unavailable: no dictionary returned.\n", stderr); return 4;
        }
        NSArray *identifiers = result[@"bundle_identifiers"];
        if (![identifiers isKindOfClass:NSArray.class]) return 5;
        for (NSString *key in @[@"responsible_bundle_identifiers", @"display_names", @"energy_impacts"]) {
            id values = result[key];
            if (![values isKindOfClass:NSArray.class] || [values count] != identifiers.count) {
                fprintf(stderr, "Unexpected response field: %s\n", key.UTF8String); return 5;
            }
        }
        if (![result[@"report_duration"] isKindOfClass:NSNumber.class] ||
            [result[@"report_duration"] doubleValue] != 120.0) return 5;
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:result
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) { fprintf(stderr, "%s\n", error.description.UTF8String); return 6; }
        fwrite(json.bytes, 1, json.length, stdout);
        putchar('\n');
        return 0;
    }
}
