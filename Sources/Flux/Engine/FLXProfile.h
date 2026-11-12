#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FLXDownloadState) {
  FLXDownloadStateInProgress,
  FLXDownloadStateComplete,
  FLXDownloadStateCanceled,
};

/// A file downloaded by a page of a profile, as it was when last updated.
NS_SWIFT_UI_ACTOR
@interface FLXDownload : NSObject
/// Chromium's id, unique while Flux runs.
@property (nonatomic, readonly) uint32_t identifier;
@property (nonatomic, readonly, copy) NSString *url;
/// Empty until the user chose where to save it, when asked.
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *mimeType;
@property (nonatomic, readonly) int64_t receivedBytes;
/// -1 when the server didn't tell.
@property (nonatomic, readonly) int64_t totalBytes;
@property (nonatomic, readonly) FLXDownloadState state;
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
@end

@class FLXBrowserView;

/// An extension's popup, open under its button until it closes.
NS_SWIFT_UI_ACTOR
@interface FLXExtensionPopup : NSObject
@property (nonatomic, readonly) NSView *view;
/// The size the page laid itself out at.
@property (nonatomic, readonly) NSSize size;
@property (nonatomic, copy, nullable) void (^onResize)(NSSize size);
/// Called when the page closes itself.
@property (nonatomic, copy, nullable) void (^onClose)(void);
- (void)close;
- (instancetype)init NS_UNAVAILABLE;
@end

/// A Chromium profile: cookies, storage, saved passwords, extensions and site settings kept in
/// one folder, apart from every other profile.
NS_SWIFT_UI_ACTOR
@interface FLXProfile : NSObject

/// Returns the profile stored at `path`. The folder has to be a direct child of the engine's root
/// cache path.
+ (instancetype)profileAtPath:(NSString *)path;

/// A profile kept in memory, as Chrome's incognito mode does: nothing is written to disk, and it
/// is all gone once the profile and its pages are released. Each call makes a new one.
+ (instancetype)privateBrowsingProfile;

/// Chromium loads a profile with its extensions, which run in processes of their own, so a profile
/// only loads when it is first needed: with its first page, or when this is called.
- (void)load;
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

/// The languages sites are asked for by default, as Chromium lists them ("fr-FR,fr,en"), for the
/// profile at a path. The user's own choice in chrome://settings/languages comes first.
@property (class, nonatomic, copy, nullable) NSString *_Nullable (^languagesProvider)(NSString *path);

@property (nonatomic, readonly, copy) NSString *path;

/// Whether downloads open a save panel instead of going straight to the Downloads folder.
@property (nonatomic) BOOL asksWhereToSaveDownloads;

/// Called each time a download of this profile starts, progresses or ends.
@property (nonatomic, copy, nullable) void (^downloadHandler)(FLXDownload *download);

/// Calls `handler` with the current value of a Chromium preference (a dictionary, array, string or
/// number), then again each time it changes. Chromium only writes preferences to disk every few
/// seconds, so files can't be relied on for this. The first call waits for the profile to load,
/// without loading it.
- (void)observePreference:(NSString *)name handler:(void (^)(id _Nullable value))handler;

/// Sets a Chromium preference of this profile, once the profile has loaded, without loading it.
- (void)setPreference:(NSString *)name boolValue:(BOOL)value;
- (void)setPreference:(NSString *)name stringValue:(NSString *)value;
- (void)setPreference:(NSString *)name stringListValue:(NSArray<NSString *> *)value;

/// Nil until the profile has loaded, or when the preference isn't a string.
- (nullable NSString *)stringPreference:(NSString *)name;

/// Runs an extension's toolbar action on a page, as a click on its button in Chrome does. Returns
/// the action's popup, if it has one.
- (nullable FLXExtensionPopup *)runActionForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page;

/// The badge an extension shows on its button for a page, such as a count. Nil for none.
- (nullable NSString *)badgeTextForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page;
- (nullable NSColor *)badgeColorForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page;

/// Called when an extension changes its button, its badge for one.
@property (nonatomic, copy, nullable) void (^actionChangeHandler)(void);

/// Opens Chromium's extension manager for this profile in a window of its own.
- (void)showExtensionsWindowWithTitle:(NSString *)title;

/// Opens `url` in a stock Chrome window of this profile, toolbar included. Used to compare how a
/// page behaves as a real Chrome tab.
- (void)showChromeWindowWithURL:(NSString *)url title:(NSString *)title;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
