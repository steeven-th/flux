#import <AppKit/AppKit.h>
#import <Security/Security.h>

#import "FLXEngine+Internal.h"
#import "FLXDevTools+Internal.h"
#import "FLXProfile+Internal.h"

#include <crt_externs.h>
#include <map>

#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

CefScopedLibraryLoader* g_library_loader = nullptr;
std::map<int, CefRefPtr<CefBrowser>> g_browsers;
bool g_ready = false;
bool g_quitting = false;
NSMutableArray<void (^)(void)>* g_ready_blocks = nil;
void (^g_external_page_handler)(NSString*, NSString*) = nil;

NSString* ToNSString(const CefString& string) {
  return [NSString stringWithUTF8String:string.ToString().c_str()] ?: @"";
}

// Windows Chromium creates through its own UI: after an extension install, or when an extension
// opens a tab. Flux never shows them. Each window keeps track of whether it still holds one of
// Chrome's own tabs (its new tab page).
NSHashTable<NSWindow*>* g_hidden_windows = nil;
NSHashTable<NSWindow*>* g_windows_with_chrome_tab = nil;
NSHashTable<NSWindow*>* g_visible_windows = nil;

// Making the window transparent is not enough: tiling window managers still lay it out next to
// Flux. It is taken off screen, and again every time Chromium shows it.
void HideChromiumWindow(NSWindow* window) {
  if (!window || [g_visible_windows containsObject:window]) return;
  if (!g_hidden_windows) {
    g_hidden_windows = [NSHashTable weakObjectsHashTable];
    g_windows_with_chrome_tab = [NSHashTable weakObjectsHashTable];
    for (NSNotificationName name in @[ NSWindowDidChangeOcclusionStateNotification,
                                       NSWindowDidBecomeKeyNotification ]) {
      [NSNotificationCenter.defaultCenter addObserverForName:name
                                                      object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification* notification) {
        NSWindow* shown = notification.object;
        if (![g_hidden_windows containsObject:shown] || !shown.isVisible) return;
        BOOL wasKey = shown.isKeyWindow;
        [shown orderOut:nil];
        if (!wasKey) return;
        for (NSWindow* other in NSApp.orderedWindows) {
          if (![g_hidden_windows containsObject:other] && other.isVisible && other.canBecomeKeyWindow) {
            [other makeKeyWindow];
            break;
          }
        }
      }];
    }
  }
  if (![g_hidden_windows containsObject:window]) {
    [g_hidden_windows addObject:window];
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    window.excludedFromWindowsMenu = YES;
  }
  [window orderOut:nil];
}

NSWindow* WindowOf(CefRefPtr<CefBrowser> browser) {
  NSView* view = (__bridge NSView*)browser->GetHost()->GetWindowHandle();
  return view.window;
}

// Client of the tabs in those windows. Their pages belong in Flux: the URL is handed over and the
// navigation canceled. Chromium keeps a pointer to the window's active tab while its "extension
// added" bubble is pending and crashes if no tab is left, so a tab is only closed when the window
// still holds a Chrome tab to fall back on.
class ExternalWindowClient : public CefClient, public CefLifeSpanHandler, public CefRequestHandler {
 public:
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    FLXEngineBrowserCreated(browser);
    HideChromiumWindow(WindowOf(browser));
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { FLXEngineBrowserClosed(browser); }

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request,
                      bool user_gesture,
                      bool is_redirect) override {
    if (!frame->IsMain()) return false;
    NSWindow* window = WindowOf(browser);
    HideChromiumWindow(window);
    NSString* url = ToNSString(request->GetURL());
    // Chrome's new tab page is what Chromium shows in an empty window of its own. Other pages,
    // Chrome's password manager included, go to Flux.
    if (url.length == 0 || [url hasPrefix:@"chrome://newtab"] || [url hasPrefix:@"chrome://new-tab-page"] ||
        [url hasPrefix:@"about:"]) {
      if (window) [g_windows_with_chrome_tab addObject:window];
      return false;
    }
    FLXEngineOpenExternalPage(url, browser);
    if (window && [g_windows_with_chrome_tab containsObject:window]) {
      browser->GetHost()->CloseBrowser(true);
    }
    return true;
  }

 private:
  IMPLEMENT_REFCOUNTING(ExternalWindowClient);
};

class App : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  CefRefPtr<CefClient> GetDefaultClient() override {
    if (!external_window_client_) external_window_client_ = new ExternalWindowClient();
    return external_window_client_;
  }

  void OnBeforeCommandLineProcessing(const CefString& process_type,
                                     CefRefPtr<CefCommandLine> command_line) override {
    if (!FLXEngine.usesSystemKeychain) command_line->AppendSwitch("use-mock-keychain");
    // The browser-wide DevTools protocol, for running extension toolbar actions. The pipe was
    // reserved at launch.
    if (FLXDevTools.isAvailable) {
      command_line->AppendSwitch("remote-debugging-pipe");
      command_line->AppendSwitch("enable-unsafe-extension-debugging");
    }
  }

  // Chromium passes --remote-debugging-pipe on to renderers, where it sets navigator.webdriver.
  // Google sign-in then refuses the browser as automated, so that flag is turned off again.
  void OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line) override {
    if (command_line->GetSwitchValue("type") != "renderer") return;
    std::string disabled = command_line->GetSwitchValue("disable-blink-features");
    command_line->AppendSwitchWithValue(
        "disable-blink-features", (disabled.empty() ? "" : disabled + ",") + "AutomationControlled");
  }

  void OnContextInitialized() override {
    g_ready = true;
    NSArray<void (^)(void)>* blocks = g_ready_blocks;
    g_ready_blocks = nil;
    for (void (^block)(void) in blocks) block();
  }

 private:
  CefRefPtr<ExternalWindowClient> external_window_client_;
  IMPLEMENT_REFCOUNTING(App);
};

}  // namespace

void FLXEngineKeepWindowVisible(NSWindow* window) {
  if (!g_visible_windows) g_visible_windows = [NSHashTable weakObjectsHashTable];
  [g_visible_windows addObject:window];
}

void FLXEngineOpenExternalPage(NSString* url, CefRefPtr<CefBrowser> browser) {
  if (!g_external_page_handler) return;
  NSString* profile_path = ToNSString(browser->GetHost()->GetRequestContext()->GetCachePath());
  void (^handler)(NSString*, NSString*) = g_external_page_handler;
  dispatch_async(dispatch_get_main_queue(), ^{
    handler(url, profile_path);
  });
}

void FLXEngineBrowserCreated(CefRefPtr<CefBrowser> browser) {
  g_browsers[browser->GetIdentifier()] = browser;
}

void FLXEngineBrowserClosed(CefRefPtr<CefBrowser> browser) {
  g_browsers.erase(browser->GetIdentifier());
  if (g_quitting && g_browsers.empty()) {
    FLXDevToolsHangUp();
    CefQuitMessageLoop();
  }
}

@implementation FLXEngine

+ (NSInteger)chromiumMajorVersion {
  return CHROME_VERSION_MAJOR;
}

+ (BOOL)usesSystemKeychain {
  static BOOL uses = NO;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    SecCodeRef code = NULL;
    SecStaticCodeRef staticCode = NULL;
    CFDictionaryRef info = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode) == errSecSuccess &&
        SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &info) == errSecSuccess) {
      // Ad hoc signatures have no team.
      uses = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) != NULL;
    }
    if (info) CFRelease(info);
    if (staticCode) CFRelease(staticCode);
    if (code) CFRelease(code);
  });
  return uses;
}

+ (BOOL)startWithRootCachePath:(NSString *)rootCachePath {
  if (g_library_loader) return YES;

  g_library_loader = new CefScopedLibraryLoader();
  if (!g_library_loader->LoadInMain()) {
    NSLog(@"Could not load the Chromium Embedded Framework");
    return NO;
  }

  [NSFileManager.defaultManager createDirectoryAtPath:rootCachePath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];

  CefMainArgs main_args(*_NSGetArgc(), *_NSGetArgv());
  CefSettings settings;
  CefString(&settings.root_cache_path) = rootCachePath.UTF8String;
  CefString(&settings.cache_path) = rootCachePath.UTF8String;
  CefString(&settings.log_file) = [rootCachePath stringByAppendingPathComponent:@"chromium.log"].UTF8String;
  settings.log_severity = LOGSEVERITY_WARNING;
  settings.persist_session_cookies = true;
  // Chromium's own pages and menus show in Flux's language, read once at launch like Flux's.
  // The languages sites are asked for are left to each profile's settings: set here, they would
  // replace the user's choice at every launch.
  NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
  CefString(&settings.locale) = language.UTF8String;

  CefRefPtr<App> app(new App());
  if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
    NSLog(@"Chromium failed to initialize (exit code %d)", CefGetExitCode());
    return NO;
  }
  return YES;
}

+ (void)runMessageLoop {
  CefRunMessageLoop();
}

+ (void)shutdown {
  FLXProfileReleaseAll();
  CefShutdown();
  delete g_library_loader;
  g_library_loader = nullptr;
}

+ (void)closeAllBrowsersAndQuit {
  g_quitting = true;
  if (g_browsers.empty()) {
    FLXDevToolsHangUp();
    CefQuitMessageLoop();
    return;
  }
  // Closing a browser removes it from the map, so iterate over a copy.
  auto browsers = g_browsers;
  for (auto& entry : browsers) {
    entry.second->GetHost()->CloseBrowser(true);
  }
  // A browser Chromium opened by itself, like a DevTools window, may never say it closed, which
  // would leave Flux running with no window. Quitting goes on without it after a while.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    if (g_browsers.empty()) return;
    NSLog(@"Quitting with %zu browsers that didn't close", g_browsers.size());
    g_browsers.clear();
    FLXDevToolsHangUp();
    CefQuitMessageLoop();
  });
}

+ (void (^)(NSString*, NSString*))externalPageHandler {
  return g_external_page_handler;
}

+ (void)setExternalPageHandler:(void (^)(NSString*, NSString*))handler {
  g_external_page_handler = [handler copy];
}

+ (void)whenReady:(void (^)(void))block {
  if (g_ready) {
    block();
    return;
  }
  if (!g_ready_blocks) g_ready_blocks = [NSMutableArray array];
  [g_ready_blocks addObject:[block copy]];
}

@end
