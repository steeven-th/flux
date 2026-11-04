#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

@class FLXBrowserView;
@class FLXProfile;

NS_ASSUME_NONNULL_BEGIN

/// Pages show with rounded corners. Views drawn around them follow this radius.
FOUNDATION_EXPORT const CGFloat FLXPageCornerRadius;

/// Chrome's zoom steps, remembered per site in the profile.
typedef NS_ENUM(NSInteger, FLXZoom) {
  FLXZoomIn,
  FLXZoomOut,
  FLXZoomReset,
};

/// How a page asked for a new one.
typedef NS_ENUM(NSInteger, FLXOpenDisposition) {
  /// A ⌘-click, a middle click or a menu item asking for a tab, shown or not.
  FLXOpenDispositionForegroundTab,
  FLXOpenDispositionBackgroundTab,
  /// A link with a target, or window.open without window features.
  FLXOpenDispositionLinkTarget,
  /// A ⇧-click, which asks Chrome for a new window.
  FLXOpenDispositionShiftClick,
};

/// What a site asks to use. A request can ask for several, camera and microphone for one.
typedef NS_OPTIONS(uint32_t, FLXPermission) {
  FLXPermissionCameraPanTiltZoom = 1 << 1,
  FLXPermissionCamera = 1 << 2,
  FLXPermissionClipboard = 1 << 4,
  FLXPermissionTopLevelStorageAccess = 1 << 5,
  FLXPermissionLocalFonts = 1 << 7,
  FLXPermissionGeolocation = 1 << 8,
  FLXPermissionIdleDetection = 1 << 11,
  FLXPermissionMicrophone = 1 << 12,
  FLXPermissionMIDI = 1 << 13,
  FLXPermissionMultipleDownloads = 1 << 14,
  FLXPermissionNotifications = 1 << 15,
  FLXPermissionKeyboardLock = 1 << 16,
  FLXPermissionPointerLock = 1 << 17,
  FLXPermissionProtocolHandler = 1 << 19,
  FLXPermissionStorageAccess = 1 << 20,
  FLXPermissionWindowManagement = 1 << 23,
  FLXPermissionFileSystem = 1 << 24,
  FLXPermissionLocalNetwork = 1 << 25 | 1 << 26 | 1 << 27,
  FLXPermissionSensors = 1 << 28,
};

/// A site asking to use something, such as notifications or the camera. Chromium keeps the answer
/// for the site, as Chrome does.
NS_SWIFT_UI_ACTOR
@interface FLXPermissionRequest : NSObject

/// The site, as an origin such as https://example.com/.
@property (nonatomic, readonly, copy) NSString *origin;
@property (nonatomic, readonly) FLXPermission permissions;
/// Called when Chromium drops the request before it is answered, when the page goes elsewhere
/// for one.
@property (nonatomic, copy, nullable) void (^onCancel)(void);

- (void)allow;
- (void)block;
/// Closes the request without an answer, so the site may ask again later.
- (void)dismiss;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_SWIFT_UI_ACTOR
@protocol FLXBrowserViewDelegate <NSObject>
@optional
- (void)browserView:(FLXBrowserView *)browserView didChangeURL:(NSString *)url;
- (void)browserView:(FLXBrowserView *)browserView didChangeTitle:(NSString *)title;
- (void)browserView:(FLXBrowserView *)browserView didChangeFavicon:(NSImage *)favicon;
/// Sent when automatic resizing is on and the page's content size changed.
- (void)browserView:(FLXBrowserView *)browserView didResizeToFit:(NSSize)size;
/// Sent when the page opens a link in a new tab or window. The new page is already loading in
/// `page`.
- (void)browserView:(FLXBrowserView *)browserView
        didOpenPage:(FLXBrowserView *)page
        disposition:(FLXOpenDisposition)disposition;
/// Sent when the page's DevTools open, in a view of their own that Flux shows next to the page.
- (void)browserView:(FLXBrowserView *)browserView didOpenDevTools:(FLXBrowserView *)devTools;
/// Sent when the page's DevTools have closed.
- (void)browserViewDidCloseDevTools:(FLXBrowserView *)browserView;
/// Sent when going back or forward becomes possible or not.
- (void)browserViewDidChangeNavigationState:(FLXBrowserView *)browserView;
/// Sent each time the page has finished loading.
- (void)browserViewDidFinishLoading:(FLXBrowserView *)browserView;
/// Sent when Chromium brings forward the page while Flux doesn't show it, as the back to tab
/// button of the picture-in-picture window does.
- (void)browserViewDidRequestShow:(FLXBrowserView *)browserView;
/// Sent when the page starts or stops playing sound from its audio and video elements, its frames
/// included.
- (void)browserView:(FLXBrowserView *)browserView didChangeAudible:(BOOL)audible;
/// Sent when what the page plays changes: whether it plays, the title and artist the site gives,
/// whether it has previous and next tracks, and its volume. Nil once nothing in the page plays
/// or has played.
- (void)browserView:(FLXBrowserView *)browserView didChangeMedia:(nullable NSDictionary<NSString *, id> *)media;
/// Sent when the page asks for a permission. Without this method, Chromium shows its own prompt,
/// which doesn't respond in Flux's windows.
- (void)browserView:(FLXBrowserView *)browserView didRequestPermission:(FLXPermissionRequest *)request;
/// Sent as a search in the page finds matches. `activeMatch` counts from 1, 0 without a match.
/// Either is -1 when it hasn't changed since the last update.
- (void)browserView:(FLXBrowserView *)browserView didFindMatches:(NSInteger)count activeMatch:(NSInteger)activeMatch;
/// Titles of items Flux adds to the page's context menu. `selectedText` is empty without a
/// selection.
- (NSArray<NSString *> *)browserView:(FLXBrowserView *)browserView
    contextMenuItemsForSelectedText:(NSString *)selectedText;
/// `point` is where the menu was opened, in screen coordinates.
- (void)browserView:(FLXBrowserView *)browserView
    didChooseContextMenuItemAtIndex:(NSInteger)index
                       selectedText:(NSString *)selectedText
                              point:(NSPoint)point;
/// Sent when the page closes itself, with window.close() for example.
- (void)browserViewDidClose:(FLXBrowserView *)browserView;
/// Sent when a page opened only to download a file, a link to it in a new tab for example, has
/// nothing left to show. The download has started or was canceled.
- (void)browserViewDidOpenOnlyDownload:(FLXBrowserView *)browserView;
@end

/// A view showing one web page, in the given profile.
///
/// A page is a real Chrome tab, so extensions see it. On macOS Chromium only shows those in windows
/// of its own, so the page lives in a borderless child window kept exactly over this view.
NS_SWIFT_UI_ACTOR
@interface FLXBrowserView : NSView

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile;

/// A page drawn inside the view itself. Extensions don't see it as a tab, which suits pages that
/// are not tabs, like extension popups.
- (instancetype)initEmbeddedWithURL:(NSString *)url profile:(FLXProfile *)profile;

@property (nonatomic, weak, nullable) id<FLXBrowserViewDelegate> delegate;
@property (nonatomic, readonly, strong) FLXProfile *profile;
@property (nonatomic, readonly, copy) NSString *currentURL;
/// The corners of the page that are rounded, all by default. Those against the developer bar or
/// the DevTools stay square.
@property (nonatomic) CACornerMask roundedCorners;
/// Darkens the page, inside its own rounded corners, while something shows over it.
@property (nonatomic, getter=isDimmed) BOOL dimmed;
@property (nonatomic, readonly, copy) NSString *title;

/// Makes the page size itself to its content, between the two sizes. Extension popups need this.
- (void)fitToContentWithMinimumSize:(NSSize)minimumSize maximumSize:(NSSize)maximumSize;

- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stopLoading;
/// Chrome's print preview, over the page.
- (void)print;
/// Chrome's save panel, which saves the page as a file.
- (void)savePage;

/// Highlights `text` in the page and selects the next match, or the previous one. `findNext`
/// keeps going from the current match rather than starting a new search.
- (void)zoom:(FLXZoom)zoom;
@property (nonatomic, getter=isAudioMuted) BOOL audioMuted;

/// Sends "play", "pause", "previous", "next" or "volume" (with `value` from 0 to 1) to what the
/// page plays.
- (void)sendMediaCommand:(NSString *)command value:(double)value;
/// 1 at the default size.
@property (nonatomic, readonly) double zoomFactor;

- (void)findText:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)stopFinding;

/// Opens Chromium's DevTools for the page, on the given panel ("console", "network"…) or the one
/// they last showed.
- (void)showDevToolsOnPanel:(nullable NSString *)panel;
@property (nonatomic, readonly, weak, nullable) FLXBrowserView *devTools;
- (void)closeDevTools;

/// The page's certificate then the ones that issued it, DER encoded. Empty without https.
@property (nonatomic, readonly) NSArray<NSData *> *certificateChain;

@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;

/// Sends a DevTools protocol method to the page and gives back its result, nil if it failed.
- (void)sendDevToolsMethod:(NSString *)method
                    params:(nullable NSDictionary<NSString *, id> *)params
                completion:(void (^)(NSDictionary<NSString *, id> *_Nullable result))completion;

/// The page's own DevTools target id, which the browser-wide protocol uses to refer to it.
- (void)devToolsTargetID:(void (^)(NSString *_Nullable targetID))completion;

/// Where Chromium anchors the popup of an extension's toolbar action: the top right corner of the
/// page, in screen coordinates. Nil for embedded pages.
@property (nonatomic, readonly, nullable) NSWindow *pageWindow;

/// Gives the keyboard to the page.
- (void)focus;

/// Runs `expression` in the page's main frame and gives back its value, nil if it failed or
/// returned nothing that converts to JSON.
- (void)evaluateJavaScript:(NSString *)expression completion:(void (^)(id _Nullable value))completion;

/// Closes the page for good. The view can't be reused afterwards.
- (void)close;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
