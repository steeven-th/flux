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

/// Opens Chromium's extension manager for this profile in a window of its own.
- (void)showExtensionsWindowWithTitle:(NSString *)title;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
