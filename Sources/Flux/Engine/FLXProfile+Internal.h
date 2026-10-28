#import "FLXProfile.h"

#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"

@interface FLXProfile ()

/// Null until the engine is ready and the profile has been created.
@property (nonatomic, readonly) CefRefPtr<CefRequestContext> requestContext;

/// Runs `block` once the profile has finished loading from disk. Browsers can't be created in a
/// profile before that.
- (void)whenReady:(void (^)(void))block;

@end

/// Drops every profile's request context. Called right before the engine shuts down.
void FLXProfileReleaseAll();
