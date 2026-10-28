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
  [super sendEvent:event];
}

// Quitting has to go through Chromium: every browser closes first, then the message loop ends
// and main() shuts the engine down.
- (void)terminate:(id)sender {
  [FLXEngine closeAllBrowsersAndQuit];
}

@end
