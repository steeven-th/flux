#import <AppKit/AppKit.h>

@class FLXBrowserView;
@class FLXProfile;

NS_ASSUME_NONNULL_BEGIN

/// Pages show with rounded corners. Views drawn around them follow this radius.
FOUNDATION_EXPORT const CGFloat FLXPageCornerRadius;

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
/// Sent when the page closes itself, with window.close() for example.
- (void)browserViewDidClose:(FLXBrowserView *)browserView;
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
/// Darkens the page, inside its own rounded corners, while something shows over it.
@property (nonatomic, getter=isDimmed) BOOL dimmed;
@property (nonatomic, readonly, copy) NSString *title;

/// Makes the page size itself to its content, between the two sizes. Extension popups need this.
- (void)fitToContentWithMinimumSize:(NSSize)minimumSize maximumSize:(NSSize)maximumSize;

- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;

/// The page's own DevTools target id, which the browser-wide protocol uses to refer to it.
- (void)devToolsTargetID:(void (^)(NSString *_Nullable targetID))completion;

/// Where Chromium anchors the popup of an extension's toolbar action: the top right corner of the
/// page, in screen coordinates. Nil for embedded pages.
@property (nonatomic, readonly, nullable) NSWindow *pageWindow;

/// Gives the keyboard to the page.
- (void)focus;

/// Closes the page for good. The view can't be reused afterwards.
- (void)close;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
