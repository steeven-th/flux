#import "FLXBrowserView.h"
#import "FLXEngine+Internal.h"
#import "FLXProfile+Internal.h"

#include "include/cef_client.h"

@interface FLXBrowserView ()
@property (nonatomic, readwrite, copy) NSString *currentURL;
@property (nonatomic, readwrite, copy) NSString *title;
- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)detachBrowser;
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
    // Popups have their own window, which CEF closes. A page lives inside our window, which must
    // stay open, so tear down its view ourselves.
    if (browser->IsPopup()) return false;
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    [view removeFromSuperview];
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

}  // namespace

@implementation FLXBrowserView {
  CefRefPtr<BrowserClient> _client;
  CefRefPtr<CefBrowser> _browser;
}

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile {
  self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
  if (!self) return nil;
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

- (void)createBrowser {
  CefWindowInfo window_info;
  NSRect bounds = self.bounds;
  window_info.SetAsChild((__bridge void *)self,
                         CefRect(0, 0, (int)MAX(bounds.size.width, 1), (int)MAX(bounds.size.height, 1)));
  CefBrowserSettings settings;
  CefBrowserHost::CreateBrowser(window_info, _client, self.currentURL.UTF8String, settings, nullptr,
                                self.profile.requestContext);
}

- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser {
  _browser = browser;
  NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
  browserView.frame = self.bounds;
  browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (void)detachBrowser {
  _browser = nullptr;
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
