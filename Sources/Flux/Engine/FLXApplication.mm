#import "FLXApplication.h"
#import "FLXEngine.h"

#include "include/cef_application_mac.h"

@interface FLXApplication () <CefAppProtocol>
@end

@implementation FLXApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
  CefScopedSendingEvent sendingEventScoper;
  // Chromium's page windows take ⌘Q as their own "Exit" command, which CEF ignores, so it would
  // never reach the Quit menu item.
  if (event.type == NSEventTypeKeyDown &&
      (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand &&
      [event.charactersIgnoringModifiers isEqualToString:@"q"]) {
    [self terminate:self];
    return;
  }
  if (event.type == NSEventTypeKeyDown && self.keyDownHandler && self.keyDownHandler(event)) {
    return;
  }
  // ⌘O is Chromium's "Open File" too. Flux's menu gets it first, and only uses it when an item
  // for it is enabled.
  if (event.type == NSEventTypeKeyDown &&
      (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand &&
      [event.charactersIgnoringModifiers isEqualToString:@"o"] && [self.mainMenu performKeyEquivalent:event]) {
    return;
  }
  // To the user, Flux's window and its pages are one window, so a click that moves between them
  // must act at once. AppKit would only use it to make the clicked window key.
  if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown) {
    NSWindow *window = event.window;
    if (window && !window.isKeyWindow && window.canBecomeKeyWindow && ![window isKindOfClass:NSPanel.class]) {
      [window makeKeyWindow];
    }
  }
  [super sendEvent:event];
}

// Quitting has to go through Chromium: every browser closes first, then the message loop ends
// and main() shuts the engine down. AppKit's own terminate: is never called, so the delegate is
// asked here.
- (void)terminate:(id)sender {
  id<NSApplicationDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(applicationShouldTerminate:)] &&
      [delegate applicationShouldTerminate:self] != NSTerminateNow) {
    return;
  }
  [FLXEngine closeAllBrowsersAndQuit];
}

@end
