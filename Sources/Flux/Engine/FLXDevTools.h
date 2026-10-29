#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Chrome's browser-wide DevTools protocol, reached over a private pipe rather than a network port.
/// Some commands, like running an extension's toolbar action, are only accepted there.
NS_SWIFT_UI_ACTOR
@interface FLXDevTools : NSObject

@property (class, nonatomic, readonly) BOOL isAvailable;

/// Takes file descriptors 3 and 4 for the pipe. Must run first thing at launch, before anything
/// else opens a file and takes those numbers.
+ (void)reservePipe;

+ (void)sendMethod:(NSString *)method
            params:(NSDictionary<NSString *, id> *)params
         sessionID:(nullable NSString *)sessionID
        completion:(void (^)(NSDictionary<NSString *, id> *_Nullable result, NSString *_Nullable error))completion;

/// Receives the protocol's events, with the session they belong to if any.
@property (class, nonatomic, copy, nullable) void (^eventHandler)
    (NSString *method, NSDictionary<NSString *, id> *params, NSString *_Nullable sessionID);

@end

NS_ASSUME_NONNULL_END
