#import "FLXBrowserView.h"
#import "FLXEngine+Internal.h"
#import "FLXProfile+Internal.h"

#include "include/cef_client.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"

@interface FLXBrowserView ()
@property (nonatomic, readwrite, copy) NSString *currentURL;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readonly) BOOL embedded;
- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)detachBrowser;
- (void)pageWindowCreated:(CefRefPtr<CefWindow>)window;
- (void)pageWindowDestroyed;
@end

namespace {

NSString *ToNSString(const CefString &string) {
  return [NSString stringWithUTF8String:string.ToString().c_str()] ?: @"";
}

class BrowserClient : public CefClient,
                      public CefLifeSpanHandler,
                      public CefDisplayHandler,
                      public CefDownloadHandler {
 public:
  explicit BrowserClient(FLXBrowserView *owner) : owner_(owner) {}

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    FLXEngineBrowserCreated(browser);
    if (!browser->IsPopup()) [owner_ attachBrowser:browser];
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    if (browser->IsPopup()) return false;
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
    if (!browser->IsPopup()) [owner_ detachBrowser];
    FLXEngineBrowserClosed(browser);
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString &url) override {
    if (browser->IsPopup() || !frame->IsMain()) return;
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
    NSString *path = [downloads URLByAppendingPathComponent:ToNSString(suggested_name)].path;
    callback->Continue(path.UTF8String, false);
    return true;
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
    if (browser->IsPopup()) return;
    FLXBrowserView *owner = owner_;
    owner.title = ToNSString(title);
    if ([owner.delegate respondsToSelector:@selector(browserView:didChangeTitle:)]) {
      [owner.delegate browserView:owner didChangeTitle:owner.title];
    }
  }

 private:
  __weak FLXBrowserView *owner_;
  IMPLEMENT_REFCOUNTING(BrowserClient);
};

class PageViewDelegate : public CefBrowserViewDelegate {
 public:
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }

 private:
  IMPLEMENT_REFCOUNTING(PageViewDelegate);
};

class PageWindowDelegate : public CefWindowDelegate {
 public:
  PageWindowDelegate(CefRefPtr<CefBrowserView> browser_view, FLXBrowserView *owner)
      : browser_view_(browser_view), owner_(owner) {}

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->AddChildView(browser_view_);
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

const CGFloat FLXPageCornerRadius = 10;

}  // namespace

@implementation FLXBrowserView {
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

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile embedded:(BOOL)embedded {
  self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
  if (!self) return nil;
  _embedded = embedded;
  _profile = profile;
  _currentURL = [url copy];
  _title = @"";
  _client = new BrowserClient(self);

  __weak FLXBrowserView *weakSelf = self;
  [profile whenReady:^{
    [weakSelf createBrowser];
  }];
  return self;
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
  CefBrowserHost::CreateBrowser(window_info, _client, self.currentURL.UTF8String, settings, nullptr,
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
  NSView *rootView = _pageNSWindow.contentView;
  rootView.wantsLayer = YES;
  rootView.layer.cornerRadius = FLXPageCornerRadius;
  rootView.layer.cornerCurve = kCACornerCurveContinuous;
  rootView.layer.masksToBounds = YES;
  [self updatePageWindow];
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
  if (_observedWindow) {
    [center removeObserver:self name:NSWindowDidResizeNotification object:_observedWindow];
  }
  _observedWindow = self.window;
  if (_observedWindow) {
    [center addObserver:self
               selector:@selector(updatePageWindow)
                   name:NSWindowDidResizeNotification
                 object:_observedWindow];
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

// The page window is a child of Flux's window, so it moves with it. Only its size and offset have
// to follow this view.
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

- (void)close {
  if (_browser) _browser->GetHost()->CloseBrowser(true);
}

@end
