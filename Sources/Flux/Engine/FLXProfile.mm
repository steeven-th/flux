#import "FLXProfile+Internal.h"
#import "FLXEngine+Internal.h"

#include "include/cef_client.h"
#include "include/views/cef_box_layout.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"

@interface FLXProfile ()
- (nullable id)preferenceValue:(NSString *)name;
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
  explicit ChromeStyleBrowserViewDelegate(ChromeToolbarType toolbar = CEF_CTT_NONE) : toolbar_(toolbar) {}

  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView> browser_view) override {
    return toolbar_;
  }

  // CEF creates the toolbar but leaves placing it to the window's owner, once the browser view is
  // in a window.
  void OnWindowChanged(CefRefPtr<CefView> view, bool added) override {
    if (!added || toolbar_ == CEF_CTT_NONE) return;
    CefRefPtr<CefView> toolbar = view->AsBrowserView()->GetChromeToolbar();
    CefRefPtr<CefWindow> window = view->GetWindow();
    if (!toolbar || !window) return;
    CefBoxLayoutSettings settings;
    settings.horizontal = false;
    CefRefPtr<CefBoxLayout> layout = window->SetToBoxLayout(settings);
    window->AddChildViewAt(toolbar, 0);
    layout->SetFlexForView(view, 1);
  }

 private:
  ChromeToolbarType toolbar_;
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

id FoundationValue(CefRefPtr<CefValue> value) {
  if (!value) return nil;
  switch (value->GetType()) {
    case VTYPE_BOOL:
      return @(value->GetBool());
    case VTYPE_INT:
      return @(value->GetInt());
    case VTYPE_DOUBLE:
      return @(value->GetDouble());
    case VTYPE_STRING:
      return [NSString stringWithUTF8String:value->GetString().ToString().c_str()];
    case VTYPE_LIST: {
      CefRefPtr<CefListValue> list = value->GetList();
      NSMutableArray *array = [NSMutableArray arrayWithCapacity:list->GetSize()];
      for (size_t i = 0; i < list->GetSize(); i++) {
        [array addObject:FoundationValue(list->GetValue(i)) ?: NSNull.null];
      }
      return array;
    }
    case VTYPE_DICTIONARY: {
      CefRefPtr<CefDictionaryValue> dictionary = value->GetDictionary();
      CefDictionaryValue::KeyList keys;
      dictionary->GetKeys(keys);
      NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:keys.size()];
      for (const CefString &key : keys) {
        id item = FoundationValue(dictionary->GetValue(key));
        if (item) result[[NSString stringWithUTF8String:key.ToString().c_str()]] = item;
      }
      return result;
    }
    default:
      return nil;
  }
}

class PreferenceObserver : public CefPreferenceObserver {
 public:
  PreferenceObserver(FLXProfile *profile, void (^handler)(id)) : profile_(profile), handler_([handler copy]) {}

  void OnPreferenceChanged(const CefString &name) override {
    FLXProfile *profile = profile_;
    NSString *key = [NSString stringWithUTF8String:name.ToString().c_str()];
    handler_([profile preferenceValue:key]);
  }

 private:
  __weak FLXProfile *profile_;
  void (^handler_)(id);
  IMPLEMENT_REFCOUNTING(PreferenceObserver);
};

}  // namespace

@implementation FLXProfile {
  CefRefPtr<CefRequestContext> _requestContext;
  BOOL _loadStarted;
  BOOL _loaded;
  NSMutableArray<void (^)(void)> *_loadedBlocks;
  std::vector<CefRefPtr<CefRegistration>> _preferenceRegistrations;
}

static NSString *_Nullable (^g_languages_provider)(NSString *) = nil;

+ (NSString *_Nullable (^)(NSString *))languagesProvider {
  return g_languages_provider;
}

+ (void)setLanguagesProvider:(NSString *_Nullable (^)(NSString *))provider {
  g_languages_provider = [provider copy];
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

// CEF keeps a context without a cache path in memory.
+ (instancetype)privateBrowsingProfile {
  return [[FLXProfile alloc] initWithPath:@""];
}

- (instancetype)initWithPath:(NSString *)path {
  self = [super init];
  if (!self) return nil;
  _path = [path copy];
  _loadedBlocks = [NSMutableArray array];
  return self;
}

- (void)load {
  if (_loadStarted) return;
  _loadStarted = YES;
  __weak FLXProfile *weakSelf = self;
  [FLXEngine whenReady:^{
    FLXProfile *profile = weakSelf;
    if (!profile) return;
    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = profile.path.UTF8String;
    settings.persist_session_cookies = true;
    NSString *languages = g_languages_provider ? g_languages_provider(profile.path) : nil;
    if (languages.length > 0) CefString(&settings.accept_language_list) = languages.UTF8String;
    profile->_requestContext = CefRequestContext::CreateContext(settings, new ProfileHandler(profile));
  }];
}

- (BOOL)isLoaded {
  return _loaded;
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

- (void)showChromeWindowWithURL:(NSString *)url title:(NSString *)title {
  [self whenReady:^{
    CefBrowserSettings settings;
    CefRefPtr<CefBrowserView> browser_view = CefBrowserView::CreateBrowserView(
        new ExtensionsWindowClient(), url.UTF8String, settings, nullptr, self->_requestContext,
        new ChromeStyleBrowserViewDelegate(CEF_CTT_NORMAL));
    CefWindow::CreateTopLevelWindow(new ExtensionsWindowDelegate(browser_view, title.UTF8String));
  }];
}

- (void)observePreference:(NSString *)name handler:(void (^)(id))handler {
  __weak FLXProfile *weakSelf = self;
  [self whenLoaded:^{
    FLXProfile *profile = weakSelf;
    if (!profile || !profile->_requestContext) return;
    CefRefPtr<CefRegistration> registration = profile->_requestContext->AddPreferenceObserver(
        name.UTF8String, new PreferenceObserver(profile, handler));
    if (registration) profile->_preferenceRegistrations.push_back(registration);
    handler([profile preferenceValue:name]);
  }];
}

- (void)setPreference:(NSString *)name boolValue:(BOOL)value {
  CefRefPtr<CefValue> preference = CefValue::Create();
  preference->SetBool(value);
  [self setPreference:name value:preference];
}

- (void)setPreference:(NSString *)name stringValue:(NSString *)value {
  CefRefPtr<CefValue> preference = CefValue::Create();
  preference->SetString(value.UTF8String);
  [self setPreference:name value:preference];
}

- (void)setPreference:(NSString *)name stringListValue:(NSArray<NSString *> *)value {
  CefRefPtr<CefListValue> list = CefListValue::Create();
  for (NSUInteger i = 0; i < value.count; i++) {
    list->SetString(i, value[i].UTF8String);
  }
  CefRefPtr<CefValue> preference = CefValue::Create();
  preference->SetList(list);
  [self setPreference:name value:preference];
}

- (void)setPreference:(NSString *)name value:(CefRefPtr<CefValue>)preference {
  __weak FLXProfile *weakSelf = self;
  [self whenLoaded:^{
    FLXProfile *profile = weakSelf;
    if (!profile || !profile->_requestContext) return;
    CefString error;
    if (!profile->_requestContext->SetPreference(name.UTF8String, preference, error)) {
      NSLog(@"Couldn't set %@: %s", name, error.ToString().c_str());
    }
  }];
}

- (NSString *)stringPreference:(NSString *)name {
  id value = [self preferenceValue:name];
  return [value isKindOfClass:NSString.class] ? value : nil;
}

- (id)preferenceValue:(NSString *)name {
  if (!_requestContext) return nil;
  return FoundationValue(_requestContext->GetPreference(name.UTF8String));
}

- (CefRefPtr<CefRequestContext>)requestContext {
  return _requestContext;
}

- (void)whenReady:(void (^)(void))block {
  [self load];
  [self whenLoaded:block];
}

- (void)whenLoaded:(void (^)(void))block {
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
  _preferenceRegistrations.clear();
  _requestContext = nullptr;
}

@end

void FLXProfileReleaseAll() {
  for (FLXProfile *profile in g_profiles.allValues) {
    [profile releaseRequestContext];
  }
  [g_profiles removeAllObjects];
}

@implementation FLXDownload

- (instancetype)initWithItem:(CefRefPtr<CefDownloadItem>)item {
  self = [super init];
  _identifier = item->GetId();
  _url = [NSString stringWithUTF8String:item->GetOriginalUrl().ToString().c_str()];
  _path = [NSString stringWithUTF8String:item->GetFullPath().ToString().c_str()];
  _mimeType = [NSString stringWithUTF8String:item->GetMimeType().ToString().c_str()];
  _receivedBytes = item->GetReceivedBytes();
  _totalBytes = item->GetTotalBytes() > 0 ? item->GetTotalBytes() : -1;
  if (item->IsComplete()) {
    _state = FLXDownloadStateComplete;
  } else if (item->IsCanceled() || item->IsInterrupted()) {
    _state = FLXDownloadStateCanceled;
  } else {
    _state = FLXDownloadStateInProgress;
  }
  return self;
}

@end
