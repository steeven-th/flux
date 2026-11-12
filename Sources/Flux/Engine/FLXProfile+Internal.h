#import <EngineCore/EngineCore.h>

#import "FLXBrowserView.h"
#import "FLXProfile.h"



@interface FLXProfile ()

/// Nil until the profile has loaded.
@property (nonatomic, readonly, nullable) ECBrowserContext *context;

/// Loads the profile if needed, then runs `block` once it has loaded. Pages can't be created in a
/// profile before that.
- (void)whenReady:(void (^)(void))block;

/// Pages of the profile, as extensions see them in chrome.tabs.
- (void)addPage:(FLXBrowserView *)page contents:(ECWebContents *)contents;
- (void)removePageContents:(ECWebContents *)contents;
- (void)activatePageContents:(ECWebContents *)contents;

@end

@interface FLXBrowserView (Engine)
@property (nonatomic, readonly, nullable) ECWebContents *engineContents;
@end
