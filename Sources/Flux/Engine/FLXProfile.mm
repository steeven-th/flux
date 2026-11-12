#import "FLXProfile+Internal.h"
#import "FLXBrowserView.h"
#import "FLXEngine.h"

@interface FLXDownload ()
- (instancetype)initWithDownload:(ECDownload *)download context:(ECBrowserContext *)context;
@end

@interface FLXProfile () <ECDownloadDelegate, ECExtensionsDelegate, ECWindowDelegate>
@end

@interface FLXExtensionPopup () <ECExtensionPopupDelegate>
- (instancetype)initWithPopup:(ECExtensionPopup *)popup;
@end

@implementation FLXExtensionPopup {
  ECExtensionPopup *_popup;
}

- (instancetype)initWithPopup:(ECExtensionPopup *)popup {
  self = [super init];
  _popup = popup;
  popup.delegate = self;
  return self;
}

- (NSView *)view {
  return _popup.view;
}

- (NSSize)size {
  return _popup.size;
}

- (void)close {
  [_popup close];
}

- (void)extensionPopupDidResize:(ECExtensionPopup *)popup {
  if (_onResize) _onResize(popup.size);
}

- (void)extensionPopupDidClose:(ECExtensionPopup *)popup {
  if (_onClose) _onClose();
}

@end

namespace {

NSMutableDictionary<NSString *, FLXProfile *> *g_profiles = nil;

// A plain window showing one of Chrome's pages, such as chrome://extensions.
void ShowPageWindow(ECBrowserContext *context, NSString *url, NSString *title) {
  ECWebContents *contents = [[ECWebContents alloc] initWithBrowserContext:context];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 720)
                                                 styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  window.title = title;
  window.releasedWhenClosed = NO;
  window.contentView = contents.view;
  [window center];
  [window makeKeyAndOrderFront:nil];
  [contents loadURL:[NSURL URLWithString:url]];
  // Kept alive with its window.
  static NSMapTable<NSWindow *, ECWebContents *> *open = [NSMapTable strongToStrongObjectsMapTable];
  [open setObject:contents forKey:window];
  __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
                                                                        object:window
                                                                         queue:NSOperationQueue.mainQueue
                                                                    usingBlock:^(NSNotification *) {
    [[open objectForKey:window] close];
    [open removeObjectForKey:window];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
  }];
}

}  // namespace

@implementation FLXProfile {
  ECBrowserContext *_context;
  ECWindow *_window;
  BOOL _loadStarted;
  NSMutableArray<void (^)(void)> *_loadedBlocks;
  NSMapTable<ECWebContents *, FLXBrowserView *> *_pages;
  NSMutableDictionary<NSString *, NSMutableArray<void (^)(id)> *> *_observers;
  NSMutableDictionary<NSString *, id> *_observedValues;
  NSTimer *_preferenceTimer;
  BOOL _private;
}

static NSString *_Nullable (^g_languages_provider)(NSString *) = nil;

+ (NSString *_Nullable (^)(NSString *))languagesProvider {
  return g_languages_provider;
}

+ (void)setLanguagesProvider:(NSString *_Nullable (^)(NSString *))provider {
  g_languages_provider = [provider copy];
}

+ (instancetype)profileAtPath:(NSString *)path {
  if (!g_profiles) g_profiles = [NSMutableDictionary dictionary];
  FLXProfile *profile = g_profiles[path];
  if (!profile) {
    profile = [[FLXProfile alloc] initWithPath:path];
    g_profiles[path] = profile;
  }
  return profile;
}

// Chrome's incognito profiles belong to a regular one, so private windows use one of their own.
+ (instancetype)privateBrowsingProfile {
  NSString *root = g_profiles.allKeys.firstObject.stringByDeletingLastPathComponent;
  FLXProfile *profile = [[FLXProfile alloc] initWithPath:@""];
  profile->_private = YES;
  FLXProfile *base = [FLXProfile profileAtPath:[root stringByAppendingPathComponent:@"Private"]];
  [base whenReady:^{
    [profile didLoadContext:base.context.offTheRecordContext];
  }];
  return profile;
}

- (instancetype)initWithPath:(NSString *)path {
  self = [super init];
  if (!self) return nil;
  _path = [path copy];
  _loadedBlocks = [NSMutableArray array];
  _pages = [NSMapTable weakToWeakObjectsMapTable];
  _observers = [NSMutableDictionary dictionary];
  _observedValues = [NSMutableDictionary dictionary];
  return self;
}

- (void)load {
  if (_loadStarted || _private) return;
  _loadStarted = YES;
  __weak FLXProfile *weakSelf = self;
  [ECBrowserContext loadWithPath:_path
                      completion:^(ECBrowserContext *context) {
    if (!context) {
      NSLog(@"Couldn't load the profile at %@", weakSelf.path);
      return;
    }
    [weakSelf didLoadContext:context];
  }];
}

- (void)didLoadContext:(ECBrowserContext *)context {
  _context = context;
  context.downloadDelegate = self;
  context.extensionsDelegate = self;
  _window = [[ECWindow alloc] initWithBrowserContext:context];
  _window.delegate = self;
  _window.focused = YES;
  NSArray<void (^)(void)> *blocks = _loadedBlocks;
  _loadedBlocks = [NSMutableArray array];
  for (void (^block)(void) in blocks) block();
}

- (BOOL)isLoaded {
  return _context != nil;
}

- (ECBrowserContext *)context {
  return _context;
}

- (void)whenReady:(void (^)(void))block {
  [self load];
  if (_context) {
    block();
    return;
  }
  [_loadedBlocks addObject:[block copy]];
}

#pragma mark - Pages

- (void)addPage:(FLXBrowserView *)page contents:(ECWebContents *)contents {
  [_pages setObject:page forKey:contents];
  _window.tabs = [_window.tabs arrayByAddingObject:contents];
}

- (void)removePageContents:(ECWebContents *)contents {
  [_pages removeObjectForKey:contents];
  NSMutableArray *tabs = [_window.tabs mutableCopy];
  [tabs removeObject:contents];
  _window.tabs = tabs;
}

- (void)activatePageContents:(ECWebContents *)contents {
  if ([_window.tabs containsObject:contents]) _window.activeTab = contents;
}

- (ECWebContents *)window:(ECWindow *)window openTabWithURL:(NSURL *)url active:(BOOL)active {
  void (^handler)(NSString *, NSString *) = FLXEngine.externalPageHandler;
  if (handler) handler(url.absoluteString, _path);
  return nil;
}

- (void)window:(ECWindow *)window activateTab:(ECWebContents *)contents {
}

- (void)window:(ECWindow *)window closeTab:(ECWebContents *)contents {
  [[_pages objectForKey:contents] close];
}

#pragma mark - Downloads

- (BOOL)asksWhereToSaveDownloads {
  return NO;
}

- (void)setAsksWhereToSaveDownloads:(BOOL)asksWhereToSaveDownloads {
}

- (void)browserContext:(ECBrowserContext *)context downloadDidUpdate:(ECDownload *)download {
  if (_downloadHandler) _downloadHandler([[FLXDownload alloc] initWithDownload:download context:context]);
}

#pragma mark - Extensions

- (void)browserContextExtensionsDidChange:(ECBrowserContext *)context {
  [self checkPreferences];
}

- (void)browserContext:(ECBrowserContext *)context
    actionDidChangeForExtension:(NSString *)identifier
                    webContents:(ECWebContents *)contents {
  if (_actionChangeHandler) _actionChangeHandler();
}

- (FLXExtensionPopup *)runActionForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page {
  ECWebContents *contents = page.engineContents;
  if (!_context || !contents) return nil;
  [self activatePageContents:contents];
  ECExtensionPopup *popup = [_context runActionForExtension:identifier inWebContents:contents];
  return popup ? [[FLXExtensionPopup alloc] initWithPopup:popup] : nil;
}

- (ECExtensionAction *)actionForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page {
  ECWebContents *contents = page.engineContents;
  return _context && contents ? [_context actionForExtension:identifier inWebContents:contents] : nil;
}

- (NSString *)badgeTextForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page {
  NSString *text = [self actionForExtension:identifier onPage:page].badgeText;
  return text.length ? text : nil;
}

- (NSColor *)badgeColorForExtension:(NSString *)identifier onPage:(FLXBrowserView *)page {
  NSColor *color = [self actionForExtension:identifier onPage:page].badgeBackgroundColor;
  return color.alphaComponent > 0 ? color : nil;
}

// The extensions as Chrome keeps them in the profile's preferences, which it only writes to disk
// every few seconds, rebuilt from the loaded ones.
- (NSDictionary *)extensionSettings {
  NSString *folder = [_path stringByAppendingPathComponent:@"Extensions"];
  NSMutableDictionary *settings = [NSMutableDictionary dictionary];
  for (ECExtension *extension in _context.extensions) {
    if (extension.builtIn) continue;
    NSString *extensionFolder = [folder stringByAppendingPathComponent:extension.identifier];
    NSArray *versions = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:extensionFolder error:nil]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    if (!versions.lastObject) continue;
    settings[extension.identifier] = @{
      @"location": @1,
      @"path": [extension.identifier stringByAppendingPathComponent:versions.lastObject],
      @"disable_reasons": extension.enabled ? @[] : @[ @1 ],
    };
  }
  return settings;
}

- (void)showExtensionsWindowWithTitle:(NSString *)title {
  [self whenReady:^{
    ShowPageWindow(self->_context, @"chrome://extensions", title);
  }];
}

- (void)showChromeWindowWithURL:(NSString *)url title:(NSString *)title {
  [self whenReady:^{
    ShowPageWindow(self->_context, url, title);
  }];
}

#pragma mark - Preferences

// EngineCore has no access to a profile's preferences. Chrome writes them to disk every few
// seconds, which is enough to read them here.
- (id)preferenceValue:(NSString *)name {
  if ([name isEqualToString:@"extensions.settings"] && _context) return [self extensionSettings];
  for (NSString *file in @[ @"Secure Preferences", @"Preferences" ]) {
    NSData *data = [NSData dataWithContentsOfFile:[_path stringByAppendingPathComponent:file]];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    for (NSString *key in [name componentsSeparatedByString:@"."]) {
      value = [value isKindOfClass:NSDictionary.class] ? value[key] : nil;
    }
    if (value) return value;
  }
  return nil;
}

- (void)observePreference:(NSString *)name handler:(void (^)(id))handler {
  __weak FLXProfile *weakSelf = self;
  [self whenReady:^{
    FLXProfile *profile = weakSelf;
    if (!profile) return;
    if (!profile->_observers[name]) profile->_observers[name] = [NSMutableArray array];
    [profile->_observers[name] addObject:[handler copy]];
    id value = [profile preferenceValue:name];
    profile->_observedValues[name] = value ?: NSNull.null;
    handler(value);
    if (!profile->_preferenceTimer) {
      profile->_preferenceTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *) {
        [weakSelf checkPreferences];
      }];
    }
  }];
}

- (void)checkPreferences {
  for (NSString *name in _observers) {
    id value = [self preferenceValue:name] ?: NSNull.null;
    if ([value isEqual:_observedValues[name]]) continue;
    _observedValues[name] = value;
    for (void (^handler)(id) in _observers[name]) handler(value == NSNull.null ? nil : value);
  }
}

- (void)setPreference:(NSString *)name boolValue:(BOOL)value {
  NSLog(@"Not set, EngineCore has no preferences: %@", name);
}

- (void)setPreference:(NSString *)name stringValue:(NSString *)value {
  NSLog(@"Not set, EngineCore has no preferences: %@", name);
}

- (void)setPreference:(NSString *)name stringListValue:(NSArray<NSString *> *)value {
  NSLog(@"Not set, EngineCore has no preferences: %@", name);
}

- (NSString *)stringPreference:(NSString *)name {
  id value = _context ? [self preferenceValue:name] : nil;
  return [value isKindOfClass:NSString.class] ? value : nil;
}

@end

@implementation FLXDownload {
  __weak ECBrowserContext *_context;
}

- (instancetype)initWithDownload:(ECDownload *)download context:(ECBrowserContext *)context {
  self = [super init];
  _context = context;
  _identifier = download.identifier;
  _url = download.URL.absoluteString ?: @"";
  _path = download.fileURL.path ?: @"";
  _mimeType = @"";
  _receivedBytes = download.receivedBytes;
  _totalBytes = download.totalBytes > 0 ? download.totalBytes : -1;
  switch (download.state) {
    case ECDownloadStateComplete:
      _state = FLXDownloadStateComplete;
      break;
    case ECDownloadStateCancelled:
    case ECDownloadStateInterrupted:
      _state = FLXDownloadStateCanceled;
      break;
    default:
      _state = FLXDownloadStateInProgress;
  }
  return self;
}

- (void)cancel {
  [_context cancelDownload:_identifier];
}

@end
