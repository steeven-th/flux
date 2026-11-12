#import <AppKit/AppKit.h>
#import <EngineCore/EngineCore.h>
#import <Security/Security.h>
#import <objc/runtime.h>

#import "FLXDevTools+Internal.h"
#import "FLXEngine.h"

namespace {

NSApplicationTerminateReply (^g_termination_handler)(void) = nil;
void (^g_open_urls_handler)(NSArray<NSURL *> *) = nil;
void (^g_external_page_handler)(NSString *, NSString *) = nil;

BOOL g_closing = NO;

// Flux asks first, for its quit confirmation. Chrome then keeps running while the DevTools pipe is
// open, so the browser is closed through it, which quits.
void AskBeforeTerminating(Class applicationClass) {
  SEL selector = @selector(terminate:);
  Method method = class_getInstanceMethod(applicationClass, selector);
  using Original = void (*)(id, SEL, id);
  Original original = (Original)method_getImplementation(method);
  method_setImplementation(method, imp_implementationWithBlock(^(NSApplication *app, id sender) {
    if (g_closing || !FLXDevTools.isAvailable) return original(app, selector, sender);
    if (g_termination_handler && g_termination_handler() != NSTerminateNow) return;
    g_closing = YES;
    [FLXDevTools sendMethod:@"Browser.close" params:@{} sessionID:nil completion:^(NSDictionary *, NSString *) {}];
  }));
}

}  // namespace

@implementation FLXEngine

+ (NSInteger)chromiumMajorVersion {
  return 156;
}

+ (BOOL)usesSystemKeychain {
  static BOOL uses = NO;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    SecCodeRef code = NULL;
    SecStaticCodeRef staticCode = NULL;
    CFDictionaryRef info = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode) == errSecSuccess &&
        SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &info) == errSecSuccess) {
      // Ad hoc signatures have no team.
      uses = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) != NULL;
    }
    if (info) CFRelease(info);
    if (staticCode) CFRelease(staticCode);
    if (code) CFRelease(code);
  });
  return uses;
}

+ (void)startWithRootCachePath:(NSString *)rootCachePath launchHandler:(void (^)(void))launchHandler {
  [NSFileManager.defaultManager createDirectoryAtPath:rootCachePath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  [center addObserverForName:NSApplicationDidFinishLaunchingNotification
                      object:nil
                       queue:NSOperationQueue.mainQueue
                  usingBlock:^(NSNotification *) {
    AskBeforeTerminating([NSApp class]);
    launchHandler();
  }];
  [center addObserverForName:ECEngineOpenURLsNotification
                      object:nil
                       queue:NSOperationQueue.mainQueue
                  usingBlock:^(NSNotification *notification) {
    if (g_open_urls_handler) g_open_urls_handler(notification.object);
  }];

  NSMutableArray<NSString *> *arguments = [NSProcessInfo.processInfo.arguments mutableCopy];
  [arguments addObject:[@"--user-data-dir=" stringByAppendingString:rootCachePath]];
  NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
  [arguments addObject:[@"--lang=" stringByAppendingString:language]];
  if (!self.usesSystemKeychain) [arguments addObject:@"--use-mock-keychain"];
  // The browser-wide DevTools protocol, for what pages need of it and for running extension
  // toolbar actions. The pipe was reserved at launch.
  if (FLXDevTools.isAvailable) {
    [arguments addObject:@"--remote-debugging-pipe"];
    [arguments addObject:@"--enable-unsafe-extension-debugging"];
    // The pipe sets navigator.webdriver in pages, and Google sign-in then refuses the browser as
    // automated.
    [arguments addObject:@"--disable-blink-features=AutomationControlled"];
  }
  [ECEngine startWithArguments:arguments];
}

+ (NSApplicationTerminateReply (^)(void))terminationHandler {
  return g_termination_handler;
}

+ (void)setTerminationHandler:(NSApplicationTerminateReply (^)(void))handler {
  g_termination_handler = [handler copy];
}

+ (void (^)(NSArray<NSURL *> *))openURLsHandler {
  return g_open_urls_handler;
}

+ (void)setOpenURLsHandler:(void (^)(NSArray<NSURL *> *))handler {
  g_open_urls_handler = [handler copy];
}

+ (void (^)(NSString *, NSString *))externalPageHandler {
  return g_external_page_handler;
}

+ (void)setExternalPageHandler:(void (^)(NSString *, NSString *))handler {
  g_external_page_handler = [handler copy];
}

@end
