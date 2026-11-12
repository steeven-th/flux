#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface FLXEngine : NSObject

/// Runs Chrome's browser process with its profiles in `rootCachePath`, and never returns.
/// `launchHandler` runs once the app has finished launching, when profiles and pages can be made.
+ (void)startWithRootCachePath:(NSString *)rootCachePath
                 launchHandler:(void (^)(void))launchHandler __attribute__((noreturn));

/// Whether Chromium keeps the key of its passwords and cookies in the keychain. Only when Flux is
/// signed with a certificate: an ad hoc signature changes with each build, and macOS would ask for
/// the keychain again every time. Builds without one use Chromium's fixed test key.
@property (class, nonatomic, readonly) BOOL usesSystemKeychain;

/// The major version of the Chromium Flux runs, which reads databases of that version or older.
@property (class, nonatomic, readonly) NSInteger chromiumMajorVersion NS_SWIFT_NONISOLATED;

/// Asked before quitting. Chrome then closes every page and quits.
@property (class, nonatomic, copy, nullable) NSApplicationTerminateReply (^terminationHandler)(void);

/// Links from other apps, and HTML files opened with Flux.
@property (class, nonatomic, copy, nullable) void (^openURLsHandler)(NSArray<NSURL *> *urls);

/// Chromium sometimes opens pages in windows of its own, for example the page an extension shows
/// after it is installed. Flux hands the page to this handler instead, with the folder of the
/// profile it belongs to.
@property (class, nonatomic, copy, nullable) void (^externalPageHandler)(NSString *url, NSString *profilePath);

@end

NS_ASSUME_NONNULL_END
