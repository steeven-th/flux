// Changed for Flux: DevTools docked in the embedder's window (ECDevTools).
#ifndef ENGINE_CORE_EC_WEB_CONTENTS_PRIVATE_H_
#define ENGINE_CORE_EC_WEB_CONTENTS_PRIVATE_H_

#import "engine_core/EngineCore.h"

#include "ui/base/window_open_disposition.h"

class GURL;

namespace content {
class WebContents;
}

namespace extensions {
class WindowController;
}

class DevToolsToggleAction;

NS_ASSUME_NONNULL_BEGIN

@interface ECWebContents ()
// The ECWebContents of `contents`, nil if the shell did not create it.
+ (nullable ECWebContents*)fromContents:(content::WebContents*)contents;
// Null once closed.
@property(readonly, nullable) content::WebContents* contents;
// Set by the window that holds the tab.
@property(weak, nullable) ECWindow* window;
// Asks the delegate for a new window, with the modifier keys of the click or
// key press behind the request when it came from one.
- (void)requestNewWindowWithURL:(const GURL&)url
                    disposition:(WindowOpenDisposition)disposition
                    userGesture:(BOOL)userGesture;
// Opens or brings forward the page's DevTools, or closes them when
// `forceOpen` is NO and they are open, as Chrome's toggle does.
- (void)toggleDevToolsForcingOpen:(BOOL)forceOpen
                           action:(const DevToolsToggleAction&)action;
@end

@interface ECDevTools ()
- (nullable instancetype)initWithInspectedWebContents:(ECWebContents*)inspected
                                              action:(const DevToolsToggleAction&)
                                                         action;
- (void)performAction:(const DevToolsToggleAction&)action;
// Destroys the frontend, quietly.
- (void)close;
@end

// Has EngineCore's pages open their DevTools docked, through their delegate.
void RegisterDevToolsHost();

@interface ECWindow ()
// Null once closed.
@property(readonly, nullable) extensions::WindowController* controller;
// The tab's status, URL, title or favicon may have changed.
- (void)tabDidUpdate:(ECWebContents*)tab;
// The tab is closing.
- (void)tabWillClose:(ECWebContents*)tab;
@end

// Replaces Chrome's chrome.tabs and chrome.windows functions that read its
// tab strips with ones that read the shell's windows.
void RegisterWindowFunctions();

NS_ASSUME_NONNULL_END

#endif  // ENGINE_CORE_EC_WEB_CONTENTS_PRIVATE_H_
