#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A Chromium profile: cookies, storage, saved passwords, extensions and site settings kept in
/// one folder, apart from every other profile.
NS_SWIFT_UI_ACTOR
@interface FLXProfile : NSObject

/// Returns the profile stored at `path`, loading it if needed. The folder has to be a direct
/// child of the engine's root cache path.
+ (instancetype)profileAtPath:(NSString *)path;

@property (nonatomic, readonly, copy) NSString *path;

/// Calls `handler` with the current value of a Chromium preference (a dictionary, array, string or
/// number), then again each time it changes. Chromium only writes preferences to disk every few
/// seconds, so files can't be relied on for this. The first call waits for the profile to load.
- (void)observePreference:(NSString *)name handler:(void (^)(id _Nullable value))handler;

/// Sets a Chromium preference of this profile, once the profile has loaded.
- (void)setPreference:(NSString *)name boolValue:(BOOL)value;

/// Opens Chromium's extension manager for this profile in a window of its own.
- (void)showExtensionsWindowWithTitle:(NSString *)title;

/// Opens `url` in a stock Chrome window of this profile, toolbar included. Used to compare how a
/// page behaves as a real Chrome tab.
- (void)showChromeWindowWithURL:(NSString *)url title:(NSString *)title;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
