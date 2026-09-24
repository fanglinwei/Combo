#import <Foundation/Foundation.h>
#include <dlfcn.h>

// Read-only private API, isolated from Combo. ABI probed on macOS 27 (26A428).
// The system Perl host follows ungive/mediaremote-adapter's loading mechanism.
@protocol MediaRequest
- (instancetype)initWithPlayerPath:(id)path;
- (void)requestPlaybackStateOnQueue:(dispatch_queue_t)queue completion:(void (^)(uint32_t, NSError *))completion;
@end
@protocol MediaPath
- (instancetype)initWithOrigin:(id)origin client:(id)client player:(id)player;
@end

static id Value(id object, NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    return [object valueForKey:key];
}

static BOOL Excluded(NSString *bundleID) {
    // Communications clients must never animate the music indicator.
    // ponytail: known app identities; browser calls/unknown communication clients need
    // a verified session-type signal before claiming universal call exclusion.
    for (NSString *prefix in @[@"local.combo.", @"com.apple.FaceTime", @"com.apple.TelephonyUtilities",
                              @"com.tencent.xinWeChat", @"com.tencent.qq", @"com.tencent.WeWork",
                              @"com.tencent.meeting", @"us.zoom.", @"com.microsoft.teams", @"com.microsoft.teams2",
                              @"com.microsoft.skype", @"com.hnc.Discord", @"com.tinyspeck.slackmacgap"]) {
        if ([bundleID isEqual:prefix] || [bundleID hasPrefix:[prefix stringByAppendingString:@"."]]
            || ([prefix hasSuffix:@"."] && [bundleID hasPrefix:prefix])) return YES;
    }
    return NO;
}

static NSDictionary *ReadState(void (*clients)(dispatch_queue_t, void (^)(NSArray *)), Class requestClass, Class pathClass, id origin, id player) {
    __block BOOL complete = NO, playing = NO, failed = NO;
    clients(dispatch_get_main_queue(), ^(NSArray *items) {
        @try {
            if (![items isKindOfClass:NSArray.class] || items.count > 256) { failed = YES; complete = YES; return; }
            __block NSUInteger remaining = items.count;
            if (!remaining) { complete = YES; return; }
            for (id client in items) {
                NSString *bundleID = Value(client, @"parentApplicationBundleIdentifier");
                if (![bundleID isKindOfClass:NSString.class] || !bundleID.length) bundleID = Value(client, @"bundleIdentifier");
                if (![bundleID isKindOfClass:NSString.class] || !bundleID.length || Excluded(bundleID)) {
                    if (!--remaining) complete = YES;
                    continue;
                }
                id path = [(id<MediaPath>)[pathClass alloc] initWithOrigin:origin client:client player:player];
                if (!path) { failed = YES; if (!--remaining) complete = YES; continue; }
                id<MediaRequest> request = [(id<MediaRequest>)[requestClass alloc] initWithPlayerPath:path];
                if (!request) { failed = YES; if (!--remaining) complete = YES; continue; }
                [request requestPlaybackStateOnQueue:dispatch_get_main_queue() completion:^(uint32_t state, NSError *error) {
                    if (error || state == 0 || state > 4) failed = YES;
                    else if (state == 1) playing = YES; // Playing; 2/3/4 = paused/stopped/interrupted.
                    if (!--remaining) complete = YES;
                }];
            }
        } @catch (NSException *exception) { failed = YES; complete = YES; }
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!complete && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    BOOL available = playing || (complete && !failed);
    return @{@"available": available ? @YES : @NO, @"playing": available && playing ? @YES : @NO};
}

// This library is loaded only by the bundled read-only Perl invocation.
#ifndef COMBO_MEDIA_CHECK
__attribute__((constructor)) static void Stream(void) {
    @autoreleasepool { @try {
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_LOCAL);
        void (*clients)(dispatch_queue_t, void (^)(NSArray *)) = framework ? dlsym(framework, "MRMediaRemoteGetNowPlayingClients") : NULL;
        Class request = NSClassFromString(@"MRNowPlayingRequest"), path = NSClassFromString(@"MRPlayerPath");
        id origin = Value(NSClassFromString(@"MROrigin"), @"localOrigin");
        id player = Value(NSClassFromString(@"MRPlayer"), @"defaultPlayer");
        if (!clients || !origin || !player || ![path instancesRespondToSelector:@selector(initWithOrigin:client:player:)]
            || ![request instancesRespondToSelector:@selector(initWithPlayerPath:)]
            || ![request instancesRespondToSelector:@selector(requestPlaybackStateOnQueue:completion:)]) exit(1);
        for (;;) { @autoreleasepool {
            NSDictionary *state = ReadState(clients, request, path, origin, player);
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
            if (!data) exit(1);
            fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout);
            // ponytail: poll registered media clients once per second; add verified all-client
            // notifications if this small read becomes measurable. Audio IO is not playback.
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        } }
    } @catch (NSException *exception) { exit(1); } }
}
#endif
