#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Chrome's own NSApplication runs the app, so Flux sees key presses through an event monitor.
NS_SWIFT_UI_ACTOR
@interface FLXApplication : NSObject

/// Sees key presses before the window does, and so before Chromium. Returns YES for one it used.
@property (class, nonatomic, copy, nullable) BOOL (^keyDownHandler)(NSEvent *event);

@end

NS_ASSUME_NONNULL_END
