#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The app's NSApplication. Chromium needs to know when AppKit is dispatching an event.
@interface FLXApplication : NSApplication
@end

NS_ASSUME_NONNULL_END
