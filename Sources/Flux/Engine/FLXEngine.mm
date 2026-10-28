#import "FLXEngine+Internal.h"
#import "FLXProfile+Internal.h"

#include <crt_externs.h>
#include <map>

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

CefScopedLibraryLoader* g_library_loader = nullptr;
std::map<int, CefRefPtr<CefBrowser>> g_browsers;
bool g_ready = false;
bool g_quitting = false;
NSMutableArray<void (^)(void)>* g_ready_blocks = nil;

class App : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnBeforeCommandLineProcessing(const CefString& process_type,
                                     CefRefPtr<CefCommandLine> command_line) override {
    // Chromium encrypts cookies and passwords with a Keychain item, and an ad hoc signed build
    // gets a new access prompt on every rebuild. Real Keychain storage comes with signing.
    command_line->AppendSwitch("use-mock-keychain");
  }

  void OnContextInitialized() override {
    g_ready = true;
    NSArray<void (^)(void)>* blocks = g_ready_blocks;
    g_ready_blocks = nil;
    for (void (^block)(void) in blocks) block();
  }

 private:
  IMPLEMENT_REFCOUNTING(App);
};

}  // namespace

void FLXEngineBrowserCreated(CefRefPtr<CefBrowser> browser) {
  g_browsers[browser->GetIdentifier()] = browser;
}

void FLXEngineBrowserClosed(CefRefPtr<CefBrowser> browser) {
  g_browsers.erase(browser->GetIdentifier());
  if (g_quitting && g_browsers.empty()) {
    CefQuitMessageLoop();
  }
}

@implementation FLXEngine

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
    CefQuitMessageLoop();
    return;
  }
  // Closing a browser removes it from the map, so iterate over a copy.
  auto browsers = g_browsers;
  for (auto& entry : browsers) {
    entry.second->GetHost()->CloseBrowser(true);
  }
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
