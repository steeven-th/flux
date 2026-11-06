#import "FLXProfile.h"

#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"

@interface FLXProfile ()

/// Null until the engine is ready and the profile has been created.
@property (nonatomic, readonly) CefRefPtr<CefRequestContext> requestContext;

/// Loads the profile if needed, then runs `block` once it has finished loading from disk.
/// Browsers can't be created in a profile before that.
- (void)whenReady:(void (^)(void))block;

/// Runs `block` once the profile has loaded, without loading it.
- (void)whenLoaded:(void (^)(void))block;

@end

#include "include/cef_download_handler.h"
#include "include/cef_download_item.h"

@interface FLXDownload ()
- (instancetype)initWithItem:(CefRefPtr<CefDownloadItem>)item
                    callback:(CefRefPtr<CefDownloadItemCallback>)callback;
@end

/// Drops every profile's request context. Called right before the engine shuts down.
void FLXProfileReleaseAll();
