#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <sys/select.h>
#include <unistd.h>

// Private MediaRemote API, isolated from Combo. ABI probed on macOS 27 (26A428).
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

#ifndef COMBO_MEDIA_CHECK
static NSString *MediaKey(void *framework, const char *name) {
    NSString * __unsafe_unretained *key = (NSString * __unsafe_unretained *)dlsym(framework, name);
    return key ? *key : nil;
}
#endif

static NSDictionary *ReadTrack(void (*getClient)(dispatch_queue_t, void (^)(id)),
                               void (*getInfo)(dispatch_queue_t, void (^)(NSDictionary *)),
                               void (*getPlaying)(dispatch_queue_t, void (^)(BOOL)),
                               NSString *titleKey, NSString *artistKey, NSString *artworkKey) {
    __block id client;
    __block NSDictionary *info;
    __block BOOL playing = NO, clientDone = NO, infoDone = NO, playingDone = NO;
    getClient(dispatch_get_main_queue(), ^(id value) { client = value; clientDone = YES; });
    getInfo(dispatch_get_main_queue(), ^(NSDictionary *value) { info = value; infoDone = YES; });
    getPlaying(dispatch_get_main_queue(), ^(BOOL value) { playing = value; playingDone = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!(clientDone && infoDone && playingDone) && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    if (!clientDone || !playingDone || !client) return nil;
    NSString *bundle = Value(client, @"parentApplicationBundleIdentifier");
    if (![bundle isKindOfClass:NSString.class] || !bundle.length) bundle = Value(client, @"bundleIdentifier");
    if (![bundle isKindOfClass:NSString.class] || !bundle.length || Excluded(bundle)) return nil;
    NSString *source = Value(client, @"displayName");
    if (![source isKindOfClass:NSString.class] || !source.length) source = bundle;
    id title = titleKey && [info isKindOfClass:NSDictionary.class] ? info[titleKey] : nil;
    id artist = artistKey && [info isKindOfClass:NSDictionary.class] ? info[artistKey] : nil;
    NSMutableDictionary *track = [@{@"title": [title isKindOfClass:NSString.class] ? title : @"",
                                    @"artist": [artist isKindOfClass:NSString.class] ? artist : @"",
                                    @"source": source, @"bundleIdentifier": bundle, @"playing": @(playing)} mutableCopy];
    id artwork = artworkKey && [info isKindOfClass:NSDictionary.class] ? info[artworkKey] : nil;
    if ([artwork isKindOfClass:NSData.class] && [artwork length] <= 512 * 1024)
        track[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
    return track;
}

static int CommandForByte(char value) {
    switch (value) {
    case 't': return 2; // toggle play/pause
    case 'n': return 4; // next track
    case 'b': return 5; // previous track
    default: return -1;
    }
}

// Perl calls this XS entry after loading the library, outside dyld's loader lock.
#ifndef COMBO_MEDIA_CHECK
__attribute__((visibility("default"))) void combo_media_stream(void *interpreter, void *cv) {
    (void)interpreter; (void)cv;
    @autoreleasepool { @try {
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_LOCAL);
        void (*clients)(dispatch_queue_t, void (^)(NSArray *)) = framework ? dlsym(framework, "MRMediaRemoteGetNowPlayingClients") : NULL;
        void (*getClient)(dispatch_queue_t, void (^)(id)) = framework ? dlsym(framework, "MRMediaRemoteGetNowPlayingClient") : NULL;
        void (*getInfo)(dispatch_queue_t, void (^)(NSDictionary *)) = framework ? dlsym(framework, "MRMediaRemoteGetNowPlayingInfo") : NULL;
        void (*getPlaying)(dispatch_queue_t, void (^)(BOOL)) = framework ? dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
        bool (*send)(int, id) = framework ? dlsym(framework, "MRMediaRemoteSendCommand") : NULL;
        Class request = NSClassFromString(@"MRNowPlayingRequest"), path = NSClassFromString(@"MRPlayerPath");
        id origin = Value(NSClassFromString(@"MROrigin"), @"localOrigin");
        id player = Value(NSClassFromString(@"MRPlayer"), @"defaultPlayer");
        if (!clients || !getClient || !getInfo || !getPlaying || !send || !origin || !player || ![path instancesRespondToSelector:@selector(initWithOrigin:client:player:)]
            || ![request instancesRespondToSelector:@selector(initWithPlayerPath:)]
            || ![request instancesRespondToSelector:@selector(requestPlaybackStateOnQueue:completion:)]) exit(1);
        NSString *titleKey = MediaKey(framework, "kMRMediaRemoteNowPlayingInfoTitle");
        NSString *artistKey = MediaKey(framework, "kMRMediaRemoteNowPlayingInfoArtist");
        NSString *artworkKey = MediaKey(framework, "kMRMediaRemoteNowPlayingInfoArtworkData");
        for (;;) { @autoreleasepool {
            NSMutableDictionary *state = [ReadState(clients, request, path, origin, player) mutableCopy];
            NSDictionary *track = ReadTrack(getClient, getInfo, getPlaying, titleKey, artistKey, artworkKey);
            if (track) {
                state[@"available"] = @YES;
                state[@"playing"] = track[@"playing"];
                state[@"track"] = track;
            }
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
            if (!data) exit(1);
            fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout);
            // ponytail: poll registered media clients once per second; add verified all-client
            // notifications if this small read becomes measurable. Audio IO is not playback.
            NSDate *next = [NSDate dateWithTimeIntervalSinceNow:1];
            while (next.timeIntervalSinceNow > 0) {
                fd_set input; FD_ZERO(&input); FD_SET(STDIN_FILENO, &input);
                struct timeval poll = {0, 0};
                if (select(STDIN_FILENO + 1, &input, NULL, NULL, &poll) > 0) {
                    char commands[32]; ssize_t count = read(STDIN_FILENO, commands, sizeof(commands));
                    if (count <= 0) exit(0);
                    for (ssize_t i = 0; i < count; i++) {
                        int command = CommandForByte(commands[i]);
                        if (command >= 0 && track) send(command, nil);
                    }
                }
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
        } }
    } @catch (NSException *exception) { exit(1); } }
}
#endif
