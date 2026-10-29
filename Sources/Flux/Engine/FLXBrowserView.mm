#import "FLXBrowserView.h"
#import "FLXEngine+Internal.h"
#import "FLXProfile+Internal.h"

#include "include/cef_parser.h"
#include "include/cef_ssl_status.h"
#include "include/cef_x509_certificate.h"

#include <map>

#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"

@interface FLXBrowserView ()
@property (nonatomic, readwrite, copy) NSString *currentURL;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readonly) BOOL embedded;
@property (nonatomic, readonly) CefRefPtr<CefClient> cefClient;
- (instancetype)initOpenedByPageWithURL:(NSString *)url profile:(FLXProfile *)profile;
- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)setCanGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)detachBrowser;
- (void)pageWindowCreated:(CefRefPtr<CefWindow>)window;
- (void)pageWindowDestroyed;
@end

namespace {

NSString *ToNSString(const CefString &string) {
  return [NSString stringWithUTF8String:string.ToString().c_str()] ?: @"";
}

class FaviconCallback : public CefDownloadImageCallback {
 public:
  explicit FaviconCallback(FLXBrowserView *owner) : owner_(owner) {}

  void OnDownloadImageFinished(const CefString &image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    FLXBrowserView *owner = owner_;
    if (!image || image->IsEmpty() || ![owner.delegate respondsToSelector:@selector(browserView:didChangeFavicon:)]) {
      return;
    }
    int width = 0;
    int height = 0;
    CefRefPtr<CefBinaryValue> png = image->GetAsPNG(2, true, width, height);
    if (!png) return;
    NSMutableData *data = [NSMutableData dataWithLength:png->GetSize()];
    png->GetData(data.mutableBytes, data.length, 0);
    NSImage *favicon = [[NSImage alloc] initWithData:data];
    if (favicon) [owner.delegate browserView:owner didChangeFavicon:favicon];
  }

 private:
  __weak FLXBrowserView *owner_;
  IMPLEMENT_REFCOUNTING(FaviconCallback);
};

// The result of one DevTools method sent to a page, nil if it failed.
class MethodResultObserver : public CefDevToolsMessageObserver {
 public:
  MethodResultObserver(int message_id, void (^completion)(NSDictionary *))
      : message_id_(message_id), completion_([completion copy]) {}

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser, int message_id, bool success,
                              const void *result, size_t result_size) override {
    if (message_id != message_id_ || !completion_) return;
    NSDictionary *json = nil;
    if (success) {
      json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:result_size]
                                             options:0
                                               error:nil];
    }
    void (^completion)(NSDictionary *) = completion_;
    completion_ = nil;
    registration_ = nullptr;
    completion(json);
  }

  CefRefPtr<CefRegistration> registration_;

 private:
  int message_id_;
  void (^completion_)(NSDictionary *);
  IMPLEMENT_REFCOUNTING(MethodResultObserver);
};

// Pages opened in a new tab, between the request and the creation of their view, by popup id.
std::map<int, FLXBrowserView *> &PendingPages() {
  static std::map<int, FLXBrowserView *> pages;
  return pages;
}

class BrowserClient : public CefClient,
                      public CefLifeSpanHandler,
                      public CefDisplayHandler,
                      public CefDownloadHandler,
                      public CefRequestHandler,
                      public CefLoadHandler {
 public:
  BrowserClient(FLXBrowserView *owner, bool opened_by_page)
      : owner_(owner), profile_(owner.profile), opened_by_page_(opened_by_page) {}

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool is_loading, bool can_go_back,
                            bool can_go_forward) override {
    if (!IsOwnPage(browser)) return;
    FLXBrowserView *owner = owner_;
    [owner setCanGoBack:can_go_back canGoForward:can_go_forward];
    if (is_loading) return;
    if ([owner.delegate respondsToSelector:@selector(browserViewDidFinishLoading:)]) {
      [owner.delegate browserViewDidFinishLoading:owner];
    }
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    FLXEngineBrowserCreated(browser);
    if (page_id_ == 0 && (opened_by_page_ || !browser->IsPopup())) {
      page_id_ = browser->GetIdentifier();
      [owner_ attachBrowser:browser];
    }
  }

  // A link ⌘-clicked, or opened in a new tab by one of Chrome's own pages. Unlike OnBeforePopup,
  // there is no opener to keep, so Flux loads the URL in a page of its own.
  bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        const CefString &target_url,
                        cef_window_open_disposition_t target_disposition,
                        bool user_gesture) override {
    if (!OpensNewTab(target_disposition)) return false;
    FLXBrowserView *owner = owner_;
    if (!owner) return false;
    if (owner.embedded || ![owner.delegate respondsToSelector:@selector(browserView:didOpenPage:disposition:)]) {
      FLXEngineOpenExternalPage(ToNSString(target_url), browser);
      return true;
    }
    FLXBrowserView *page = [[FLXBrowserView alloc] initWithURL:ToNSString(target_url) profile:owner.profile];
    [owner.delegate browserView:owner didOpenPage:page disposition:Disposition(target_disposition, false)];
    return true;
  }

  // Links opened in a new tab become Flux tabs. Their page is still created by Chromium, as a
  // popup, so it keeps its link to the opener, which some sign-in flows rely on. Popups asked
  // with window features stay windows.
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString &target_url,
                     const CefString &target_frame_name,
                     cef_window_open_disposition_t target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures &popup_features,
                     CefWindowInfo &window_info,
                     CefRefPtr<CefClient> &client,
                     CefBrowserSettings &settings,
                     CefRefPtr<CefDictionaryValue> &extra_info,
                     bool *no_javascript_access) override {
    if (!OpensNewTab(target_disposition)) return false;
    FLXBrowserView *owner = owner_;
    if (!owner) return false;
    // An embedded page can't host Chrome style popups.
    if (owner.embedded) {
      FLXEngineOpenExternalPage(ToNSString(target_url), browser);
      return true;
    }
    if (![owner.delegate respondsToSelector:@selector(browserView:didOpenPage:disposition:)]) return false;
    FLXBrowserView *page = [[FLXBrowserView alloc] initOpenedByPageWithURL:ToNSString(target_url)
                                                                   profile:owner.profile];
    client = page.cefClient;
    PendingPages()[popup_id] = page;
    FLXOpenDisposition disposition = Disposition(target_disposition, true);
    dispatch_async(dispatch_get_main_queue(), ^{
      [owner.delegate browserView:owner didOpenPage:page disposition:disposition];
    });
    return false;
  }

  void OnBeforePopupAborted(CefRefPtr<CefBrowser> browser, int popup_id) override {
    PendingPages().erase(popup_id);
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    if (!IsOwnPage(browser)) return false;
    FLXBrowserView *owner = owner_;
    if ([owner.delegate respondsToSelector:@selector(browserViewDidClose:)]) {
      [owner.delegate browserViewDidClose:owner];
    }
    // A page window is closed by CEF like any other window. An embedded page lives inside Flux's
    // window, which must stay open, so its view is torn down here.
    if (!owner.embedded) return false;
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    [view removeFromSuperview];
    return true;
  }

  bool OnAutoResize(CefRefPtr<CefBrowser> browser, const CefSize &new_size) override {
    FLXBrowserView *owner = owner_;
    if ([owner.delegate respondsToSelector:@selector(browserView:didResizeToFit:)]) {
      [owner.delegate browserView:owner didResizeToFit:NSMakeSize(new_size.width, new_size.height)];
    }
    return true;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    if (IsOwnPage(browser)) [owner_ detachBrowser];
    FLXEngineBrowserClosed(browser);
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString &url) override {
    if (!IsOwnPage(browser) || !frame->IsMain()) return;
    FLXBrowserView *owner = owner_;
    owner.currentURL = ToNSString(url);
    if ([owner.delegate respondsToSelector:@selector(browserView:didChangeURL:)]) {
      [owner.delegate browserView:owner didChangeURL:owner.currentURL];
    }
  }

  // Without this handler every download is canceled, including the extension packages that the
  // Chrome Web Store downloads when installing.
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString &suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override {
    if (download_item->GetMimeType() == "application/x-chrome-extension") {
      // An empty path keeps the package in Chromium's temporary folder, where the installer reads it.
      callback->Continue("", false);
      return true;
    }
    NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
    NSString *path = AvailablePath([downloads URLByAppendingPathComponent:ToNSString(suggested_name)].path);
    callback->Continue(path.UTF8String, profile_.asksWhereToSaveDownloads);
    return true;
  }

  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override {
    if (download_item->GetMimeType() == "application/x-chrome-extension") return;
    if (profile_.downloadHandler) profile_.downloadHandler([[FLXDownload alloc] initWithItem:download_item]);
  }

  // "name (1).ext", "name (2).ext"… next to a file of the same name, as Chrome does.
  static NSString *AvailablePath(NSString *path) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *base = path.stringByDeletingPathExtension;
    NSString *extension = path.pathExtension;
    NSString *candidate = path;
    for (int number = 1; [files fileExistsAtPath:candidate]; number++) {
      NSString *name = [NSString stringWithFormat:@"%@ (%d)", base, number];
      candidate = extension.length ? [name stringByAppendingPathExtension:extension] : name;
    }
    return candidate;
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString> &icon_urls) override {
    if (!IsOwnPage(browser) || icon_urls.empty()) return;
    browser->GetHost()->DownloadImage(icon_urls.front(), true, 64, false, new FaviconCallback(owner_));
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
    if (!IsOwnPage(browser)) return;
    FLXBrowserView *owner = owner_;
    owner.title = ToNSString(title);
    if ([owner.delegate respondsToSelector:@selector(browserView:didChangeTitle:)]) {
      [owner.delegate browserView:owner didChangeTitle:owner.title];
    }
  }

 private:
  // A foreground tab asked by the page itself, rather than by a ⌘-click, comes from a link target
  // or window.open.
  static FLXOpenDisposition Disposition(cef_window_open_disposition_t disposition, bool from_page) {
    switch (disposition) {
      case CEF_WOD_NEW_BACKGROUND_TAB:
        return FLXOpenDispositionBackgroundTab;
      case CEF_WOD_NEW_WINDOW:
        return FLXOpenDispositionShiftClick;
      default:
        return from_page ? FLXOpenDispositionLinkTarget : FLXOpenDispositionForegroundTab;
    }
  }

  static bool OpensNewTab(cef_window_open_disposition_t disposition) {
    return disposition == CEF_WOD_NEW_FOREGROUND_TAB || disposition == CEF_WOD_NEW_BACKGROUND_TAB ||
           disposition == CEF_WOD_NEW_WINDOW;
  }

  bool IsOwnPage(CefRefPtr<CefBrowser> browser) const { return browser->GetIdentifier() == page_id_; }

  __weak FLXBrowserView *owner_;
  // Kept for downloads that outlive their tab.
  FLXProfile *profile_;
  const bool opened_by_page_;
  int page_id_ = 0;
  IMPLEMENT_REFCOUNTING(BrowserClient);
};

class PageWindowDelegate : public CefWindowDelegate {
 public:
  PageWindowDelegate(CefRefPtr<CefBrowserView> browser_view, FLXBrowserView *owner)
      : browser_view_(browser_view), owner_(owner) {}

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->AddChildView(browser_view_);
    if (CefRefPtr<CefView> toolbar = browser_view_->GetChromeToolbar()) toolbar->SetVisible(false);
    [owner_ pageWindowCreated:window];
  }

  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    browser_view_ = nullptr;
    [owner_ pageWindowDestroyed];
  }

  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  bool IsFrameless(CefRefPtr<CefWindow> window) override { return true; }
  // Flux sizes the window. A resizable one would also grab drags just outside its edges.
  bool CanResize(CefRefPtr<CefWindow> window) override { return false; }
  bool CanMinimize(CefRefPtr<CefWindow> window) override { return false; }
  bool CanMaximize(CefRefPtr<CefWindow> window) override { return false; }
  CefRect GetInitialBounds(CefRefPtr<CefWindow> window) override { return CefRect(-10000, -10000, 800, 600); }

  bool CanClose(CefRefPtr<CefWindow> window) override {
    CefRefPtr<CefBrowser> browser = browser_view_ ? browser_view_->GetBrowser() : nullptr;
    return !browser || browser->GetHost()->TryCloseBrowser();
  }

 private:
  CefRefPtr<CefBrowserView> browser_view_;
  __weak FLXBrowserView *owner_;
  IMPLEMENT_REFCOUNTING(PageWindowDelegate);
};

class PageViewDelegate : public CefBrowserViewDelegate {
 public:
  PageViewDelegate() = default;
  explicit PageViewDelegate(FLXBrowserView *opened_page) : opened_page_(opened_page) {}

  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
  // Chrome anchors extension popups to its toolbar's extension area, and running an extension's
  // action fails without one. The toolbar exists but stays hidden, Flux has its own.
  ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView> browser_view) override {
    return CEF_CTT_NORMAL;
  }

  CefRefPtr<CefBrowserViewDelegate> GetDelegateForPopupBrowserView(CefRefPtr<CefBrowserView> browser_view,
                                                                   const CefBrowserSettings &settings,
                                                                   CefRefPtr<CefClient> client,
                                                                   bool is_devtools) override {
    auto &pending = PendingPages();
    for (auto it = pending.begin(); it != pending.end(); ++it) {
      if (it->second.cefClient.get() != client.get()) continue;
      FLXBrowserView *page = it->second;
      pending.erase(it);
      return new PageViewDelegate(page);
    }
    return new PageViewDelegate();
  }

  // Every popup delegate comes from the method above, so the cast is safe.
  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> browser_view,
                                 CefRefPtr<CefBrowserView> popup_browser_view,
                                 bool is_devtools) override {
    auto *delegate = static_cast<PageViewDelegate *>(popup_browser_view->GetDelegate().get());
    FLXBrowserView *page = delegate ? delegate->opened_page_ : nil;
    if (!page) return false;
    CefWindow::CreateTopLevelWindow(new PageWindowDelegate(popup_browser_view, page));
    return true;
  }

 private:
  FLXBrowserView *opened_page_ = nil;
  IMPLEMENT_REFCOUNTING(PageViewDelegate);
};

}  // namespace

// macOS already rounds the page's window by about 17 points. A larger radius here is the only one
// that shows, so the shadow drawn under the page can follow it exactly.
const CGFloat FLXPageCornerRadius = 18;

@implementation FLXBrowserView {
  NSView *_dimView;
  CefRefPtr<BrowserClient> _client;
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<CefWindow> _pageWindow;
  NSWindow *_pageNSWindow;
  NSWindow *_observedWindow;
  BOOL _fitsContent;
  NSSize _minimumSize;
  NSSize _maximumSize;
}

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile {
  return [self initWithURL:url profile:profile embedded:NO];
}

- (instancetype)initEmbeddedWithURL:(NSString *)url profile:(FLXProfile *)profile {
  return [self initWithURL:url profile:profile embedded:YES];
}

// Chromium creates the page itself, as a popup of the page that opened it.
- (instancetype)initOpenedByPageWithURL:(NSString *)url profile:(FLXProfile *)profile {
  self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
  if (!self) return nil;
  _profile = profile;
  _currentURL = [url copy];
  _title = @"";
  _client = new BrowserClient(self, true);
  return self;
}

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile embedded:(BOOL)embedded {
  self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
  if (!self) return nil;
  _embedded = embedded;
  _profile = profile;
  _currentURL = [url copy];
  _title = @"";
  _client = new BrowserClient(self, false);

  __weak FLXBrowserView *weakSelf = self;
  [profile whenReady:^{
    [weakSelf createBrowser];
  }];
  return self;
}

- (CefRefPtr<CefClient>)cefClient {
  return _client;
}

// In a popover, vibrancy would wash out the page's colors.
- (BOOL)allowsVibrancy {
  return NO;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)createBrowser {
  CefBrowserSettings settings;
  if (!_embedded) {
    CefRefPtr<CefBrowserView> browser_view = CefBrowserView::CreateBrowserView(
        _client, self.currentURL.UTF8String, settings, nullptr, self.profile.requestContext,
        new PageViewDelegate());
    CefWindow::CreateTopLevelWindow(new PageWindowDelegate(browser_view, self));
    return;
  }
  CefWindowInfo window_info;
  NSRect bounds = self.bounds;
  window_info.SetAsChild((__bridge void *)self,
                         CefRect(0, 0, (int)MAX(bounds.size.width, 1), (int)MAX(bounds.size.height, 1)));
  CefRefPtr<CefDictionaryValue> extra_info = CefDictionaryValue::Create();
  // Read by the renderer, in FluxHelper.
  extra_info->SetBool("extension_popup", true);
  CefBrowserHost::CreateBrowser(window_info, _client, self.currentURL.UTF8String, settings, extra_info,
                                self.profile.requestContext);
}

- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser {
  _browser = browser;
  if (!_embedded) return;
  NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
  browserView.frame = self.bounds;
  browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  if (_fitsContent) [self applyFitToContent];
}

- (void)fitToContentWithMinimumSize:(NSSize)minimumSize maximumSize:(NSSize)maximumSize {
  _fitsContent = YES;
  _minimumSize = minimumSize;
  _maximumSize = maximumSize;
  if (_browser) [self applyFitToContent];
}

- (void)applyFitToContent {
  _browser->GetHost()->SetAutoResizeEnabled(
      true, CefSize((int)_minimumSize.width, (int)_minimumSize.height),
      CefSize((int)_maximumSize.width, (int)_maximumSize.height));
}

- (void)detachBrowser {
  _browser = nullptr;
}

#pragma mark - Page window

- (void)pageWindowCreated:(CefRefPtr<CefWindow>)window {
  _pageWindow = window;
  NSView *contentView = (__bridge NSView *)window->GetWindowHandle();
  _pageNSWindow = contentView.window;
  _pageNSWindow.opaque = NO;
  _pageNSWindow.backgroundColor = NSColor.clearColor;
  // The system gives the key window a large shadow, which would spill over the sidebar whenever
  // the page has focus. Flux draws a light one of its own under the page.
  _pageNSWindow.hasShadow = NO;
  // A non-opaque window lets clicks through wherever its own backing is transparent, which is
  // everywhere here since Chromium draws the page in a layer of its own. Setting this explicitly
  // makes the whole window take clicks.
  _pageNSWindow.ignoresMouseEvents = NO;
  // Window managers such as AeroSpace move every standard window on its own, and would leave the
  // page behind when Flux's window goes to another workspace. They leave alone windows that don't
  // present themselves as standard windows.
  _pageNSWindow.accessibilitySubrole = NSAccessibilityUnknownSubrole;
  NSView *rootView = _pageNSWindow.contentView;
  rootView.wantsLayer = YES;
  rootView.layer.cornerRadius = FLXPageCornerRadius;
  // Circular corners, which the shadow drawn under the page can follow exactly. Core Animation's
  // continuous corners don't match any path AppKit or SwiftUI draws.
  rootView.layer.cornerCurve = kCACornerCurveCircular;
  rootView.layer.masksToBounds = YES;
  [self updatePageWindow];
}

- (void)setDimmed:(BOOL)dimmed {
  _dimmed = dimmed;
  NSView *rootView = _pageNSWindow.contentView;
  if (!rootView) return;
  if (!_dimView) {
    _dimView = [[NSView alloc] initWithFrame:rootView.bounds];
    _dimView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _dimView.wantsLayer = YES;
    _dimView.layer.backgroundColor = [NSColor.blackColor colorWithAlphaComponent:0.25].CGColor;
  }
  if (dimmed) {
    _dimView.frame = rootView.bounds;
    _dimView.alphaValue = 0;
    [rootView addSubview:_dimView positioned:NSWindowAbove relativeTo:nil];
    _dimView.animator.alphaValue = 1;
  } else {
    [_dimView removeFromSuperview];
  }
}

- (void)pageWindowDestroyed {
  [_pageNSWindow.parentWindow removeChildWindow:_pageNSWindow];
  _pageWindow = nullptr;
  _pageNSWindow = nil;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (_embedded || _observedWindow == self.window) {
    [self updatePageWindow];
    return;
  }
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  NSArray<NSNotificationName> *names = @[ NSWindowDidResizeNotification, NSWindowDidMoveNotification ];
  for (NSNotificationName name in names) {
    if (_observedWindow) [center removeObserver:self name:name object:_observedWindow];
  }
  _observedWindow = self.window;
  for (NSNotificationName name in names) {
    if (_observedWindow) {
      [center addObserver:self selector:@selector(updatePageWindow) name:name object:_observedWindow];
    }
  }
  [self updatePageWindow];
}

- (void)setFrameSize:(NSSize)newSize {
  [super setFrameSize:newSize];
  [self updatePageWindow];
}

- (void)setFrameOrigin:(NSPoint)newOrigin {
  [super setFrameOrigin:newOrigin];
  [self updatePageWindow];
}

- (void)viewDidHide {
  [super viewDidHide];
  [self updatePageWindow];
}

- (void)viewDidUnhide {
  [super viewDidUnhide];
  [self updatePageWindow];
}

// The page window is a child of Flux's window, so it normally moves with it. Its frame is still set
// again whenever Flux's window moves or resizes, in case something moved one without the other.
- (void)updatePageWindow {
  if (_embedded || !_pageWindow || !_pageNSWindow) return;
  NSWindow *host = self.window;
  BOOL visible = host && !self.isHiddenOrHasHiddenAncestor && self.bounds.size.width > 0;
  if (!visible) {
    [_pageNSWindow.parentWindow removeChildWindow:_pageNSWindow];
    if (_pageNSWindow.isVisible) _pageWindow->Hide();
    return;
  }
  NSRect frame = [host convertRectToScreen:[self convertRect:self.bounds toView:nil]];
  if (_pageNSWindow.parentWindow != host) {
    [_pageNSWindow.parentWindow removeChildWindow:_pageNSWindow];
    [host addChildWindow:_pageNSWindow ordered:NSWindowAbove];
  }
  [_pageNSWindow setFrame:frame display:YES];
  if (!_pageNSWindow.isVisible) _pageWindow->Show();
}

- (NSWindow *)pageWindow {
  return _pageNSWindow;
}

- (void)devToolsTargetID:(void (^)(NSString *))completion {
  [self sendCefDevToolsMethod:"Target.getTargetInfo" params:nullptr completion:^(NSDictionary *result) {
    completion(result[@"targetInfo"][@"targetId"]);
  }];
}

- (void)evaluateJavaScript:(NSString *)expression completion:(void (^)(id))completion {
  CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
  params->SetString("expression", expression.UTF8String);
  params->SetBool("returnByValue", true);
  [self sendCefDevToolsMethod:"Runtime.evaluate" params:params completion:^(NSDictionary *result) {
    completion(result[@"result"][@"value"]);
  }];
}

- (void)sendCefDevToolsMethod:(const char *)method
                       params:(CefRefPtr<CefDictionaryValue>)params
                   completion:(void (^)(NSDictionary *))completion {
  if (!_browser) {
    completion(nil);
    return;
  }
  static int next_message_id = 1;
  int message_id = next_message_id++;
  CefRefPtr<MethodResultObserver> observer = new MethodResultObserver(message_id, completion);
  observer->registration_ = _browser->GetHost()->AddDevToolsMessageObserver(observer);
  _browser->GetHost()->ExecuteDevToolsMethod(message_id, method, params);
}

- (void)focus {
  if (_pageNSWindow.isVisible) [_pageNSWindow makeKeyWindow];
  if (_browser) _browser->GetHost()->SetFocus(true);
}

- (void)loadURL:(NSString *)url {
  self.currentURL = url;
  if (_browser) _browser->GetMainFrame()->LoadURL(url.UTF8String);
}

- (void)goBack {
  if (_browser) _browser->GoBack();
}

- (void)goForward {
  if (_browser) _browser->GoForward();
}

- (void)reload {
  if (_browser) _browser->Reload();
}

- (NSArray<NSData *> *)certificateChain {
  if (!_browser) return @[];
  CefRefPtr<CefNavigationEntry> entry = _browser->GetHost()->GetVisibleNavigationEntry();
  CefRefPtr<CefSSLStatus> status = entry ? entry->GetSSLStatus() : nullptr;
  CefRefPtr<CefX509Certificate> certificate = status ? status->GetX509Certificate() : nullptr;
  if (!certificate) return @[];
  NSMutableArray<NSData *> *chain = [NSMutableArray array];
  auto append = [chain](CefRefPtr<CefBinaryValue> der) {
    if (!der) return;
    NSMutableData *data = [NSMutableData dataWithLength:der->GetSize()];
    der->GetData(data.mutableBytes, data.length, 0);
    [chain addObject:data];
  };
  append(certificate->GetDEREncoded());
  CefX509Certificate::IssuerChainBinaryList issuers;
  certificate->GetDEREncodedIssuerChain(issuers);
  for (auto &issuer : issuers) append(issuer);
  return chain;
}

- (void)reloadIgnoringCache {
  if (_browser) _browser->ReloadIgnoreCache();
}

- (void)setCanGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward {
  if (canGoBack == _canGoBack && canGoForward == _canGoForward) return;
  _canGoBack = canGoBack;
  _canGoForward = canGoForward;
  if ([self.delegate respondsToSelector:@selector(browserViewDidChangeNavigationState:)]) {
    [self.delegate browserViewDidChangeNavigationState:self];
  }
}

- (void)sendDevToolsMethod:(NSString *)method
                    params:(NSDictionary<NSString *, id> *)params
                completion:(void (^)(NSDictionary<NSString *, id> *))completion {
  CefRefPtr<CefDictionaryValue> values;
  if (params) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    CefRefPtr<CefValue> parsed = CefParseJSON(text.UTF8String, JSON_PARSER_RFC);
    if (parsed) values = parsed->GetDictionary();
  }
  [self sendCefDevToolsMethod:method.UTF8String params:values completion:completion];
}

- (void)close {
  if (_browser) _browser->GetHost()->CloseBrowser(true);
}

@end
