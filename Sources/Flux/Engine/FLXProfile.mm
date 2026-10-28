#import "FLXProfile+Internal.h"
#import "FLXEngine.h"

@interface FLXProfile ()
- (void)didFinishLoading;
- (void)releaseRequestContext;
@end

namespace {

NSMutableDictionary<NSString *, FLXProfile *> *g_profiles = nil;

class ProfileHandler : public CefRequestContextHandler {
 public:
  explicit ProfileHandler(FLXProfile *profile) : profile_(profile) {}

  void OnRequestContextInitialized(CefRefPtr<CefRequestContext> request_context) override {
    [profile_ didFinishLoading];
  }

 private:
  __weak FLXProfile *profile_;
  IMPLEMENT_REFCOUNTING(ProfileHandler);
};

}  // namespace

@implementation FLXProfile {
  CefRefPtr<CefRequestContext> _requestContext;
  BOOL _loaded;
  NSMutableArray<void (^)(void)> *_loadedBlocks;
}

+ (instancetype)profileAtPath:(NSString *)path {
  if (!g_profiles) g_profiles = [NSMutableDictionary dictionary];
  FLXProfile *profile = g_profiles[path];
  if (!profile) {
    profile = [[FLXProfile alloc] initWithPath:path];
    g_profiles[path] = profile;
  }
  return profile;
}

- (instancetype)initWithPath:(NSString *)path {
  self = [super init];
  if (!self) return nil;
  _path = [path copy];
  _loadedBlocks = [NSMutableArray array];

  __weak FLXProfile *weakSelf = self;
  [FLXEngine whenReady:^{
    FLXProfile *profile = weakSelf;
    if (!profile) return;
    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = profile.path.UTF8String;
    settings.persist_session_cookies = true;
    profile->_requestContext = CefRequestContext::CreateContext(settings, new ProfileHandler(profile));
  }];
  return self;
}

- (CefRefPtr<CefRequestContext>)requestContext {
  return _requestContext;
}

- (void)whenReady:(void (^)(void))block {
  if (_loaded) {
    block();
    return;
  }
  [_loadedBlocks addObject:[block copy]];
}

- (void)didFinishLoading {
  _loaded = YES;
  NSArray<void (^)(void)> *blocks = _loadedBlocks;
  _loadedBlocks = [NSMutableArray array];
  for (void (^block)(void) in blocks) block();
}

- (void)releaseRequestContext {
  _requestContext = nullptr;
}

@end

void FLXProfileReleaseAll() {
  for (FLXProfile *profile in g_profiles.allValues) {
    [profile releaseRequestContext];
  }
  [g_profiles removeAllObjects];
}
