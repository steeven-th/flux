#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface FLXEngine : NSObject

/// Loads the Chromium framework and initializes it. Must run before anything else touches the
/// engine, after the shared FLXApplication exists.
+ (BOOL)startWithRootCachePath:(NSString *)rootCachePath;

/// Whether Chromium keeps the key of its passwords and cookies in the keychain. Only when Flux is
/// signed with a certificate: an ad hoc signature changes with each build, and macOS would ask for
/// the keychain again every time. Builds without one use Chromium's fixed test key.
@property (class, nonatomic, readonly) BOOL usesSystemKeychain;

/// The major version of the Chromium Flux runs, which reads databases of that version or older.
@property (class, nonatomic, readonly) NSInteger chromiumMajorVersion NS_SWIFT_NONISOLATED;

/// Runs the AppKit event loop through Chromium. Returns once the engine has quit.
+ (void)runMessageLoop;

+ (void)shutdown;

/// Closes every browser, then leaves the message loop once the last one is gone.
+ (void)closeAllBrowsersAndQuit;

/// Runs `block` once the engine's global context is ready, right away if it already is.
+ (void)whenReady:(void (^)(void))block;

/// Chromium sometimes opens pages in windows of its own, for example the page an extension shows
/// after it is installed. Flux closes those windows and hands the page to this handler instead,
/// with the folder of the profile it belongs to.
@property (class, nonatomic, copy, nullable) void (^externalPageHandler)(NSString *url, NSString *profilePath);

@end

NS_ASSUME_NONNULL_END
