#import <AppKit/AppKit.h>

@class FLXBrowserView;
@class FLXProfile;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@protocol FLXBrowserViewDelegate <NSObject>
@optional
- (void)browserView:(FLXBrowserView *)browserView didChangeURL:(NSString *)url;
- (void)browserView:(FLXBrowserView *)browserView didChangeTitle:(NSString *)title;
@end

/// A view showing one web page, in the given profile.
NS_SWIFT_UI_ACTOR
@interface FLXBrowserView : NSView

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile;

@property (nonatomic, weak, nullable) id<FLXBrowserViewDelegate> delegate;
@property (nonatomic, readonly, strong) FLXProfile *profile;
@property (nonatomic, readonly, copy) NSString *currentURL;
@property (nonatomic, readonly, copy) NSString *title;

- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;

/// Closes the page for good. The view can't be reused afterwards.
- (void)close;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
