// Process-local private audio adapter; never injected into another process.
// Mechanism documented by raulgg/airpods-control/SECURITY.md (see research report).
#include <CoreFoundation/CoreFoundation.h>
#include <Security/SecTask.h>
#include <dlfcn.h>
#include <stdlib.h>

static CFTypeRef ProbeEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error) {
    if (entitlement && CFEqual(entitlement, CFSTR("com.apple.avfoundation.allow-system-wide-context"))) {
        if (error) *error = NULL;
        return CFRetain(kCFBooleanTrue);
    }
    typedef CFTypeRef (*Original)(SecTaskRef, CFStringRef, CFErrorRef *);
    Original original = (Original)dlsym(RTLD_NEXT, "SecTaskCopyValueForEntitlement");
    if (!original) abort();
    return original(task, entitlement, error);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } interpose = {
    (const void *)ProbeEntitlement, (const void *)SecTaskCopyValueForEntitlement
};
