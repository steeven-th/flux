#import "FLXProfile+Internal.h"
#import "FLXEngine+Internal.h"

#include "include/cef_client.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"

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

// chrome://extensions only renders in Chrome style, which needs a window made by CEF's Views
// framework rather than a view inside Flux's window.
class ExtensionsWindowClient : public CefClient, public CefLifeSpanHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    if (view.window) FLXEngineKeepWindowVisible(view.window);
    FLXEngineBrowserCreated(browser);
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { FLXEngineBrowserClosed(browser); }

 private:
  IMPLEMENT_REFCOUNTING(ExtensionsWindowClient);
};

class ChromeStyleBrowserViewDelegate : public CefBrowserViewDelegate {
 public:
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView> browser_view) override {
    return CEF_CTT_NONE;
  }

 private:
  IMPLEMENT_REFCOUNTING(ChromeStyleBrowserViewDelegate);
};

class ExtensionsWindowDelegate : public CefWindowDelegate {
 public:
  ExtensionsWindowDelegate(CefRefPtr<CefBrowserView> browser_view, const CefString &title)
      : browser_view_(browser_view), title_(title) {}

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->AddChildView(browser_view_);
    window->SetTitle(title_);
    window->CenterWindow(CefSize(960, 720));
    window->Show();
  }

  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override { browser_view_ = nullptr; }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }

  bool CanClose(CefRefPtr<CefWindow> window) override {
    CefRefPtr<CefBrowser> browser = browser_view_ ? browser_view_->GetBrowser() : nullptr;
    return !browser || browser->GetHost()->TryCloseBrowser();
  }

 private:
  CefRefPtr<CefBrowserView> browser_view_;
  CefString title_;
  IMPLEMENT_REFCOUNTING(ExtensionsWindowDelegate);
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

- (void)showExtensionsWindowWithTitle:(NSString *)title {
  [self whenReady:^{
    CefBrowserSettings settings;
    CefRefPtr<CefBrowserView> browser_view = CefBrowserView::CreateBrowserView(
        new ExtensionsWindowClient(), "chrome://extensions", settings, nullptr, self->_requestContext,
        new ChromeStyleBrowserViewDelegate());
    CefWindow::CreateTopLevelWindow(new ExtensionsWindowDelegate(browser_view, title.UTF8String));
  }];
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
