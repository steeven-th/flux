#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The app's NSApplication. Chromium needs to know when AppKit is dispatching an event.
@interface FLXApplication : NSApplication

/// Sees key presses before the window does, and so before Chromium. Returns YES for one it used.
@property (nonatomic, copy, nullable) BOOL (^keyDownHandler)(NSEvent *event);

@end

NS_ASSUME_NONNULL_END
