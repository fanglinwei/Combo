#define COMBO_MEDIA_CHECK
#import "../Combo/MediaPlaybackHelper.m"
#include <assert.h>

@interface TestClient : NSObject
@property NSString *bundleIdentifier;
@property NSString *parentApplicationBundleIdentifier;
@property NSString *displayName;
@property uint32_t state;
@end
@implementation TestClient
@end
@interface TestPath : NSObject <MediaPath>
@property TestClient *client;
@end
@implementation TestPath
- (instancetype)initWithOrigin:(id)origin client:(id)client player:(id)player {
    (void)origin; (void)player;
    if ((self = [super init])) self.client = client;
    return self;
}
@end
@interface TestRequest : NSObject <MediaRequest>
@property TestPath *path;
@end
@implementation TestRequest
- (instancetype)initWithPlayerPath:(id)path {
    if ((self = [super init])) self.path = path;
    return self;
}
- (void)requestPlaybackStateOnQueue:(dispatch_queue_t)queue completion:(void (^)(uint32_t, NSError *))completion {
    dispatch_async(queue, ^{ completion(self.path.client.state, nil); });
}
@end

static NSArray *testClients;
static NSDictionary *testInfo;
static BOOL testPlaying;
static void Clients(dispatch_queue_t queue, void (^completion)(NSArray *)) {
    dispatch_async(queue, ^{ completion(testClients); });
}
static void CurrentClient(dispatch_queue_t queue, void (^completion)(id)) {
    dispatch_async(queue, ^{ completion(testClients.firstObject); });
}
static void CurrentInfo(dispatch_queue_t queue, void (^completion)(NSDictionary *)) {
    dispatch_async(queue, ^{ completion(testInfo); });
}
static void CurrentPlaying(dispatch_queue_t queue, void (^completion)(BOOL)) {
    dispatch_async(queue, ^{ completion(testPlaying); });
}
static TestClient *Client(NSString *bundle, uint32_t state) {
    TestClient *client = TestClient.new; client.bundleIdentifier = bundle; client.state = state; return client;
}
static void Check(NSArray *clients, BOOL available, BOOL playing) {
    testClients = clients;
    NSDictionary *result = ReadState(Clients, TestRequest.class, TestPath.class, @1, @1);
    assert([result[@"available"] boolValue] == available);
    assert([result[@"playing"] boolValue] == playing);
    assert(CFGetTypeID((__bridge CFTypeRef)result[@"available"]) == CFBooleanGetTypeID());
    assert(CFGetTypeID((__bridge CFTypeRef)result[@"playing"]) == CFBooleanGetTypeID());
}
int main(void) { @autoreleasepool {
    TestClient *music = Client(@"com.netease.163music", 1), *paused = Client(@"com.apple.Music", 2);
    Check(@[], YES, NO);
    Check(@[music, paused], YES, YES); // A paused current client must not mask another playing app.
    Check(@[paused, music], YES, YES);
    music.parentApplicationBundleIdentifier = @"";
    Check(@[music], YES, YES);
    music.parentApplicationBundleIdentifier = @"com.apple.FaceTime";
    Check(@[music], YES, NO);
    music.parentApplicationBundleIdentifier = nil;
    music.state = 2; Check(@[music, paused], YES, NO);
    music.state = 3; Check(@[music], YES, NO);
    music.state = 4; Check(@[music], YES, NO);
    music.state = 0; Check(@[music], NO, NO);
    music.state = 99; Check(@[music], NO, NO);
    Check(@[music, Client(@"com.tencent.QQMusic", 1)], YES, YES);
    for (NSString *bundle in @[@"com.apple.FaceTime", @"us.zoom.xos", @"com.tencent.xinWeChat",
                              @"com.microsoft.teams2", @"com.hnc.Discord", @"local.combo.preview"])
        assert(Excluded(bundle));
    Check(@[Client(@"us.zoom.xos", 1), Client(@"com.apple.FaceTime", 1)], YES, NO);
    assert(!Excluded(@"com.tencent.QQMusic") && !Excluded(@"com.netease.163music") && !Excluded(@"com.google.Chrome"));
    testClients = @[Client(@"com.apple.Music", 1)];
    ((TestClient *)testClients.firstObject).displayName = @"Music";
    testInfo = @{@"title": @"Song", @"artist": @"Artist", @"art": [@"cover" dataUsingEncoding:NSUTF8StringEncoding]};
    testPlaying = YES;
    NSDictionary *track = ReadTrack(CurrentClient, CurrentInfo, CurrentPlaying, @"title", @"artist", @"art");
    assert([track[@"title"] isEqual:@"Song"] && [track[@"source"] isEqual:@"Music"]);
    assert([track[@"artwork"] isEqual:@"Y292ZXI="] && [track[@"playing"] boolValue]);
    testPlaying = NO;
    assert(![ReadTrack(CurrentClient, CurrentInfo, CurrentPlaying, @"title", @"artist", @"art")[@"playing"] boolValue]);
    testClients = @[Client(@"com.apple.FaceTime", 1)];
    assert(ReadTrack(CurrentClient, CurrentInfo, CurrentPlaying, @"title", @"artist", @"art") == nil);
    assert(CommandForByte('t') == 2 && CommandForByte('n') == 4 && CommandForByte('b') == 5 && CommandForByte('x') == -1);
    puts("PASS: all-client aggregation, pause/stop/interruption, unknown state and communications exclusions");
} }
