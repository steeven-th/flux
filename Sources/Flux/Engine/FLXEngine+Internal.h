#import <AppKit/AppKit.h>

#import "FLXEngine.h"

#include "include/cef_browser.h"

void FLXEngineBrowserCreated(CefRefPtr<CefBrowser> browser);
void FLXEngineBrowserClosed(CefRefPtr<CefBrowser> browser);

/// Opens the URL in a Flux tab of the browser's profile.
void FLXEngineOpenExternalPage(NSString *url, CefRefPtr<CefBrowser> browser);

/// Chromium windows Flux opens on purpose, which must never be hidden.
void FLXEngineKeepWindowVisible(NSWindow *window);
