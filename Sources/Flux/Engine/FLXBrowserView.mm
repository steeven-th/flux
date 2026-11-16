#import "FLXBrowserView.h"
#import "FLXDevTools.h"
#import "FLXProfile+Internal.h"

#import <EngineCore/EngineCore.h>

namespace {

// A page whose video is in picture-in-picture goes on to tell itself visible. Its tab is hidden, and
// players such as Twitch's lower the quality of a hidden page's stream, even watched in the window.
NSString *const kPictureInPictureShim = @R"(
(() => {
  const prototype = Document.prototype;
  for (const [name, value] of [['visibilityState', 'visible'], ['hidden', false]]) {
    const property = Object.getOwnPropertyDescriptor(prototype, name);
    if (!property?.get) continue;
    Object.defineProperty(prototype, name, {
      ...property,
      get() { return this.pictureInPictureElement ? value : property.get.call(this); },
    });
  }
  document.addEventListener('visibilitychange', (event) => {
    if (document.pictureInPictureElement) event.stopImmediatePropagation();
  }, true);
})();
)";

// What the frame plays, for the mini player: the title and artist the site gives, its previous and
// next track actions and its volume. Chrome knows whether the page plays, but not these.
NSString *const kMediaWatcher = @R"(
(() => {
  const report = (state) => globalThis.__fluxMedia?.postMessage(state);
  const handlers = new Map();
  const elements = new Set();
  let hasPlayed = false;
  let lastState = '';
  const latest = () => [...elements].reverse().find((element) => !element.paused) ?? [...elements].pop();
  const isPlaying = () => elements.size > 0
    ? [...elements].some((element) => !element.paused && !element.ended)
    : navigator.mediaSession?.playbackState === 'playing';
  const send = () => {
    if (!hasPlayed) return;
    const metadata = navigator.mediaSession?.metadata;
    const state = JSON.stringify({
      playing: isPlaying(),
      title: metadata?.title ?? '',
      artist: metadata?.artist ?? '',
      previous: handlers.has('previoustrack'),
      next: handlers.has('nexttrack'),
      volume: latest()?.volume ?? 1,
    });
    if (state === lastState) return;
    lastState = state;
    report(state);
  };
  const isContent = (element) => !(element.srcObject instanceof MediaStream) && element.duration >= 5;
  const isAudible = (element) => !element.muted && element.volume > 0
    && (element.webkitAudioDecodedByteCount ?? 1) > 0;
  const note = (element) => {
    if (!elements.has(element) && (element.paused || !isContent(element) || !isAudible(element))) return;
    elements.delete(element);
    elements.add(element);
    if (!element.paused) hasPlayed = true;
    send();
  };
  const prototype = navigator.mediaSession && Object.getPrototypeOf(navigator.mediaSession);
  if (prototype) {
    const setActionHandler = prototype.setActionHandler;
    prototype.setActionHandler = function (action, handler) {
      if (typeof handler === 'function') handlers.set(action, handler); else handlers.delete(action);
      const result = setActionHandler.apply(this, arguments);
      send();
      return result;
    };
    for (const name of ['metadata', 'playbackState']) {
      const property = Object.getOwnPropertyDescriptor(prototype, name);
      if (!property?.set) continue;
      Object.defineProperty(prototype, name, {
        ...property,
        set(value) {
          property.set.call(this, value);
          if (name === 'playbackState' && value === 'playing') hasPlayed = true;
          send();
        },
      });
    }
  }
  const types = ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange', 'timeupdate'];
  for (const type of types) {
    document.addEventListener(type, (event) => {
      if (event.target instanceof HTMLMediaElement) note(event.target);
    }, true);
  }
  const watched = new WeakSet();
  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () {
    if (!this.isConnected && !watched.has(this)) {
      watched.add(this);
      for (const type of types) this.addEventListener(type, () => note(this));
    }
    return play.apply(this, arguments);
  };
  globalThis[Symbol.for('flux.setVolume')] = (value) => {
    elements.forEach((element) => { element.volume = value; });
    send();
  };
})();
)";

NSString *const kMediaObject = @"__fluxMedia";

// The Chrome Web Store asks to switch to Chrome in a popup and a banner, and names Chrome on its
// install button, which installs in Flux all the same. The popup and the banner are hidden with a
// style sheet, which the store's own scripts don't notice. 276336 is the store's logging id for the
// banner's button.
NSString *const kWebStoreFixes = @R"(
(() => {
  if (location.hostname !== 'chromewebstore.google.com') return;
  const style = document.createElement('style');
  style.textContent = `
    header [aria-labelledby="promo-header"],
    main section div:has(> div > div > button[jslog^="276336;"]) { display: none !important; }
  `;
  document.documentElement.append(style);
  const rename = (node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.nodeValue.replace(/\b(Google )?Chrome\b/, 'Flux');
      if (text !== node.nodeValue) node.nodeValue = text;
      return;
    }
    node.childNodes.forEach(rename);
  };
  new MutationObserver(() => {
    for (const title of document.querySelectorAll('main section h1')) {
      const section = title.parentElement?.parentElement;
      const button = [...(section?.querySelectorAll('button') ?? [])].find((item) => item.textContent.includes('Chrome'));
      if (button) rename(button);
    }
  }).observe(document, { childList: true, subtree: true, characterData: true });
})();
)";

FLXPermission PermissionForKey(NSString *key) {
  static NSDictionary<NSString *, NSNumber *> *permissions = @{
    @"media_stream_camera": @(FLXPermissionCamera),
    @"camera_pan_tilt_zoom": @(FLXPermissionCameraPanTiltZoom),
    @"media_stream_mic": @(FLXPermissionMicrophone),
    @"clipboard": @(FLXPermissionClipboard),
    @"top_level_storage_access": @(FLXPermissionTopLevelStorageAccess),
    @"storage_access": @(FLXPermissionStorageAccess),
    @"local_fonts": @(FLXPermissionLocalFonts),
    @"geolocation": @(FLXPermissionGeolocation),
    @"idle_detection": @(FLXPermissionIdleDetection),
    @"midi_sysex": @(FLXPermissionMIDI),
    @"midi": @(FLXPermissionMIDI),
    @"automatic_downloads": @(FLXPermissionMultipleDownloads),
    @"notifications": @(FLXPermissionNotifications),
    @"keyboard_lock": @(FLXPermissionKeyboardLock),
    @"pointer_lock": @(FLXPermissionPointerLock),
    @"protocol_handler": @(FLXPermissionProtocolHandler),
    @"window_management": @(FLXPermissionWindowManagement),
    @"file_system_write_guard": @(FLXPermissionFileSystem),
    @"local_network_access": @(FLXPermissionLocalNetwork),
    @"sensors": @(FLXPermissionSensors),
  };
  return (FLXPermission)permissions[key].unsignedIntValue;
}

CACornerMask AllCorners() {
  return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
}

}  // namespace

const CGFloat FLXPageCornerRadius = 18;

@interface FLXPermissionRequest ()
- (instancetype)initWithOrigin:(NSString *)origin
                   permissions:(FLXPermission)permissions
                    completion:(void (^)(BOOL allow))completion;
@end

@implementation FLXPermissionRequest {
  void (^_completion)(BOOL);
}

- (instancetype)initWithOrigin:(NSString *)origin
                   permissions:(FLXPermission)permissions
                    completion:(void (^)(BOOL))completion {
  self = [super init];
  if (!self) return nil;
  _origin = [origin copy];
  _permissions = permissions;
  _completion = [completion copy];
  return self;
}

- (void)allow {
  [self answer:YES];
}

- (void)block {
  [self answer:NO];
}

- (void)dismiss {
  [self answer:NO];
}

- (void)answer:(BOOL)allow {
  void (^completion)(BOOL) = _completion;
  _completion = nil;
  if (completion) completion(allow);
}

@end

typedef NS_ENUM(NSInteger, FLXSaveOfferAnswer) {
  FLXSaveOfferAnswerSave,
  FLXSaveOfferAnswerDecline,
  FLXSaveOfferAnswerIgnore,
};

@implementation FLXSaveOffer {
  void (^_answer)(FLXSaveOfferAnswer);
}

- (instancetype)initWithKind:(FLXSaveOfferKind)kind
                      update:(BOOL)update
                       lines:(NSArray<NSString *> *)lines
                      answer:(void (^)(FLXSaveOfferAnswer))answer {
  self = [super init];
  if (!self) return nil;
  _kind = kind;
  _update = update;
  _lines = [lines copy];
  _answer = [answer copy];
  return self;
}

- (void)save {
  [self answer:FLXSaveOfferAnswerSave];
}

- (void)decline {
  [self answer:FLXSaveOfferAnswerDecline];
}

- (void)ignore {
  [self answer:FLXSaveOfferAnswerIgnore];
}

- (void)answer:(FLXSaveOfferAnswer)answer {
  void (^block)(FLXSaveOfferAnswer) = _answer;
  _answer = nil;
  if (block) block(answer);
}

@end

@implementation FLXDeviceChooser {
  ECChooser *_chooser;
}

- (instancetype)initWithChooser:(ECChooser *)chooser {
  self = [super init];
  if (!self) return nil;
  _chooser = chooser;
  __weak FLXDeviceChooser *weakSelf = self;
  chooser.updateHandler = ^{
    FLXDeviceChooser *strong = weakSelf;
    if (strong.onChange) strong.onChange();
  };
  chooser.dismissHandler = ^{
    FLXDeviceChooser *strong = weakSelf;
    if (strong.onCancel) strong.onCancel();
  };
  return self;
}

- (NSString *)title { return _chooser.title; }
- (NSString *)emptyText { return _chooser.noOptionsText; }
- (NSString *)selectTitle { return _chooser.selectButtonTitle; }
- (NSArray<NSString *> *)options { return _chooser.options; }
- (BOOL)isScanning { return _chooser.isScanning; }
- (BOOL)canRescan { return _chooser.canRescan; }
- (BOOL)isBluetoothOff { return _chooser.adapterState == ECChooserAdapterStateOff; }
- (BOOL)isBluetoothRefused { return _chooser.adapterState == ECChooserAdapterStateUnauthorized; }
- (void)selectOptionAtIndex:(NSUInteger)index { [_chooser selectOptionAtIndex:index]; }
- (void)cancel { [_chooser cancel]; }
- (void)rescan { [_chooser rescan]; }
- (void)openSystemSettings { [_chooser openSystemSettings]; }

@end

static NSArray<NSString *> *AddressLines(ECAddress *address) {
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  NSString *cityLine = [[@[ address.postalCode, address.city ] filteredArrayUsingPredicate:
      [NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
  NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObjects:address.name, address.organization, nil];
  [candidates addObjectsFromArray:address.streetLines];
  [candidates addObjectsFromArray:@[ cityLine, address.region, address.country, address.email, address.phone ]];
  for (NSString *line in candidates) {
    if (line.length) [lines addObject:line];
  }
  return lines;
}

// A borderless window can't take the keyboard by default, and the page needs it, Escape included.
@interface FLXFullscreenWindow : NSWindow
@end

@implementation FLXFullscreenWindow

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (BOOL)canBecomeMainWindow {
  return YES;
}

@end

// A context menu item that runs a block.
@interface FLXBlockMenuItem : NSMenuItem
@end

@implementation FLXBlockMenuItem {
  void (^_block)(void);
}

- (instancetype)initWithTitle:(NSString *)title block:(void (^)(void))block {
  if (!(self = [super initWithTitle:title action:@selector(run:) keyEquivalent:@""])) return nil;
  _block = [block copy];
  self.target = self;
  return self;
}

- (void)run:(id)sender {
  _block();
}

@end

@interface FLXPageDevTools () <ECDevToolsDelegate>
- (instancetype)initWithDevTools:(ECDevTools *)devTools;
@end

@implementation FLXPageDevTools {
  ECDevTools *_devTools;
}

- (instancetype)initWithDevTools:(ECDevTools *)devTools {
  if (!(self = [super init])) return nil;
  _devTools = devTools;
  devTools.delegate = self;
  return self;
}

- (NSView *)view {
  return _devTools.view;
}

- (NSRect)pageFrame {
  return _devTools.inspectedPageBounds;
}

- (void)showPanel:(NSString *)panel {
  [_devTools showPanel:panel];
}

- (void)devTools:(ECDevTools *)devTools didSetInspectedPageBounds:(NSRect)bounds {
  if (_onPageFrameChange) _onPageFrameChange();
}

@end

@interface FLXBrowserView () <ECWebContentsDelegate>
@property (nonatomic, readwrite, copy) NSString *currentURL;
@property (nonatomic, readwrite, copy) NSString *title;
@end

@implementation FLXBrowserView {
  ECWebContents *_contents;
  NSView *_dimView;
  BOOL _embedded;
  BOOL _audible;
  BOOL _loading;
  NSImage *_favicon;
  NSString *_pageID;
  NSString *_targetID;
  NSString *_sessionID;
  NSMutableArray<void (^)(NSString *)> *_sessionWaiters;
  // What each frame that played something reports, as JSON.
  NSMutableDictionary<NSString *, NSString *> *_mediaStates;
  NSString *_shownMedia;
  FLXPageDevTools *_devTools;
  // While the page shows an element full screen, its view is in this window, and goes back to
  // where it was.
  NSWindow *_fullscreenWindow;
  NSView *_fullscreenOrigin;
  NSRect _fullscreenOriginFrame;
  NSApplicationPresentationOptions _presentationBeforeFullscreen;
  id _escapeMonitor;
  // Where the link under the pointer leads, in the page's bottom left corner as in Chrome, clear
  // of its rounded corner.
  NSTextField *_linkLabel;
}

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile {
  return [self initWithURL:url profile:profile embedded:NO];
}

- (instancetype)initEmbeddedWithURL:(NSString *)url profile:(FLXProfile *)profile {
  return [self initWithURL:url profile:profile embedded:YES];
}

- (instancetype)initWithURL:(NSString *)url profile:(FLXProfile *)profile embedded:(BOOL)embedded {
  return [self initWithURL:url profile:profile embedded:embedded contents:nil];
}

// A page another one opened, which the engine created already so that it keeps its opener.
- (instancetype)initWithOpenedContents:(ECWebContents *)contents URL:(NSString *)url profile:(FLXProfile *)profile {
  return [self initWithURL:url profile:profile embedded:NO contents:contents];
}

- (instancetype)initWithURL:(NSString *)url
                    profile:(FLXProfile *)profile
                   embedded:(BOOL)embedded
                   contents:(ECWebContents *)contents {
  self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
  if (!self) return nil;
  _profile = profile;
  _embedded = embedded;
  _currentURL = [url copy];
  _title = @"";
  _pageID = NSUUID.UUID.UUIDString;
  _mediaStates = [NSMutableDictionary dictionary];
  self.wantsLayer = YES;
  self.layer.cornerRadius = FLXPageCornerRadius;
  self.layer.cornerCurve = kCACornerCurveCircular;
  self.layer.maskedCorners = AllCorners();
  self.layer.masksToBounds = YES;
  if (contents) {
    [self setUpContents:contents];
    return self;
  }
  __weak FLXBrowserView *weakSelf = self;
  [profile whenReady:^{
    [weakSelf createContents];
  }];
  return self;
}

- (void)createContents {
  [self setUpContents:[[ECWebContents alloc] initWithBrowserContext:_profile.context]];
  if (_currentURL.length) [_contents loadURL:[NSURL URLWithString:_currentURL]];
}

- (void)setUpContents:(ECWebContents *)contents {
  _contents = contents;
  _contents.delegate = self;
  // Lets the page be found among the DevTools protocol's targets.
  [_contents addDocumentStartScript:[NSString stringWithFormat:
      @"Object.defineProperty(globalThis, Symbol.for('flux.page'), {value: '%@'});", _pageID]];
  [_contents addDocumentStartScript:kPictureInPictureShim];
  [_contents addDocumentStartScript:kWebStoreFixes];
  [_contents addMessageObjectNamed:kMediaObject];
  [_contents addDocumentStartScript:kMediaWatcher];
  NSView *view = _contents.view;
  view.frame = self.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self addSubview:view positioned:NSWindowBelow relativeTo:nil];
  if (!_embedded) [_profile addPage:self contents:_contents];
}

// In a popover, vibrancy would wash out the page's colors.
- (BOOL)allowsVibrancy {
  return NO;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window && _contents && !_embedded) [_profile activatePageContents:_contents];
}

- (CACornerMask)roundedCorners {
  return self.layer.maskedCorners;
}

- (void)setRoundedCorners:(CACornerMask)roundedCorners {
  self.layer.maskedCorners = roundedCorners;
}

- (void)setDimmed:(BOOL)dimmed {
  _dimmed = dimmed;
  if (!_dimView) {
    _dimView = [[NSView alloc] initWithFrame:self.bounds];
    _dimView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _dimView.wantsLayer = YES;
    _dimView.layer.backgroundColor = [NSColor.blackColor colorWithAlphaComponent:0.25].CGColor;
  }
  if (dimmed) {
    _dimView.frame = self.bounds;
    _dimView.alphaValue = 0;
    [self addSubview:_dimView positioned:NSWindowAbove relativeTo:nil];
    _dimView.animator.alphaValue = 1;
  } else {
    [_dimView removeFromSuperview];
  }
}

#pragma mark - Navigation

- (void)loadURL:(NSString *)url {
  self.currentURL = url;
  NSURL *parsed = [NSURL URLWithString:url];
  if (parsed) [_contents loadURL:parsed];
}

- (void)goBack {
  [_contents goBack];
}

- (void)goForward {
  [_contents goForward];
}

- (void)reload {
  [_contents reload];
}

- (void)reloadIgnoringCache {
  [_contents reloadBypassingCache];
}

- (void)stopLoading {
  [_contents stop];
}

- (void)print {
  [_contents print];
}

- (void)savePage {
  [_contents savePage];
}

- (BOOL)canGoBack {
  return _contents.canGoBack;
}

- (BOOL)canGoForward {
  return _contents.canGoForward;
}

- (void)zoom:(FLXZoom)zoom {
  switch (zoom) {
    case FLXZoomIn: [_contents zoomIn]; break;
    case FLXZoomOut: [_contents zoomOut]; break;
    case FLXZoomReset: [_contents resetZoom]; break;
  }
}

- (double)zoomFactor {
  return _contents ? _contents.zoomPercent / 100.0 : 1;
}

- (BOOL)isAudioMuted {
  return _contents.muted;
}

- (void)setAudioMuted:(BOOL)audioMuted {
  _contents.muted = audioMuted;
}

- (void)sendMediaCommand:(NSString *)command value:(double)value {
  if ([command isEqualToString:@"play"]) {
    [_contents playMedia];
  } else if ([command isEqualToString:@"pause"]) {
    [_contents pauseMedia];
  } else if ([command isEqualToString:@"previous"]) {
    [_contents previousTrack];
  } else if ([command isEqualToString:@"next"]) {
    [_contents nextTrack];
  } else if ([command isEqualToString:@"volume"]) {
    NSString *script = [NSString stringWithFormat:@"globalThis[Symbol.for('flux.setVolume')]?.(%f)", value];
    [self evaluateJavaScript:script completion:^(id) {}];
  }
}

- (void)findText:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext {
  if (findNext) {
    [_contents findString:text forward:forward];
  } else {
    [_contents findString:text];
  }
}

- (void)stopFinding {
  [_contents stopFinding];
}

- (NSArray<NSData *> *)certificateChain {
  return _contents ? _contents.certificateChain : @[];
}

- (NSDictionary<NSString *, NSNumber *> *)sitePermissions {
  return _contents ? _contents.sitePermissions : @{};
}

- (void)setSitePermission:(NSString *)permission allowed:(BOOL)allowed {
  [_contents setSitePermission:permission allowed:allowed];
}

- (void)resetSitePermission:(NSString *)permission {
  [_contents resetSitePermission:permission];
}

- (void)clearSiteDataWithCompletion:(void (^)(void))completion {
  NSURL *url = _contents.URL;
  if (!url || !_profile.context) return completion();
  [_profile.context clearSiteDataForURL:url completion:completion];
}

- (void)focus {
  if (_contents) [self.window makeFirstResponder:_contents.view];
}

- (ECWebContents *)engineContents {
  return _contents;
}

- (void)close {
  if (!_contents) return;
  [self leaveFullscreenWindow];
  if (!_embedded) [_profile removePageContents:_contents];
  [_contents close];
  _contents = nil;
}

#pragma mark - DevTools

- (void)showDevToolsOnPanel:(NSString *)panel {
  [_contents showDevTools];
  if (panel) [_devTools showPanel:panel];
}

- (void)showElementPicker {
  [_contents inspectElement];
}

- (FLXPageDevTools *)devTools {
  return _devTools;
}

- (void)closeDevTools {
  [_contents closeDevTools];
}

- (void)webContents:(ECWebContents *)contents didOpenDevTools:(ECDevTools *)devTools {
  _devTools = [[FLXPageDevTools alloc] initWithDevTools:devTools];
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserView:didOpenDevTools:)]) [delegate browserView:self didOpenDevTools:_devTools];
}

- (void)webContentsDidCloseDevTools:(ECWebContents *)contents {
  _devTools = nil;
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserViewDidCloseDevTools:)]) [delegate browserViewDidCloseDevTools:self];
}

#pragma mark - Link under the pointer

- (void)webContents:(ECWebContents *)contents didUpdateTargetURL:(NSURL *)url {
  if (!url) {
    _linkLabel.hidden = YES;
    return;
  }
  if (!_linkLabel) {
    _linkLabel = [NSTextField labelWithString:@""];
    _linkLabel.font = [NSFont systemFontOfSize:11];
    _linkLabel.textColor = NSColor.secondaryLabelColor;
    _linkLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _linkLabel.drawsBackground = YES;
    _linkLabel.backgroundColor = NSColor.windowBackgroundColor;
    _linkLabel.wantsLayer = YES;
    _linkLabel.layer.cornerRadius = 5;
    _linkLabel.layer.masksToBounds = YES;
    _linkLabel.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  }
  NSString *text = url.absoluteString;
  for (NSString *scheme in @[ @"https://", @"http://" ]) {
    if ([text hasPrefix:scheme]) text = [text substringFromIndex:scheme.length];
  }
  _linkLabel.stringValue = [NSString stringWithFormat:@" %@ ", text.stringByRemovingPercentEncoding ?: text];
  [_linkLabel sizeToFit];
  CGFloat width = MIN(_linkLabel.frame.size.width + 6, MAX(self.bounds.size.width / 2, 200));
  _linkLabel.frame = NSMakeRect(8, 8, width, _linkLabel.frame.size.height + 4);
  _linkLabel.hidden = NO;
  if (_linkLabel.superview != self) [self addSubview:_linkLabel positioned:NSWindowAbove relativeTo:nil];
}

#pragma mark - Full screen

// A video's full screen button or Element.requestFullscreen(). Chromium already lays the page out
// as filling its view, so the view only has to fill the screen.
- (void)webContents:(ECWebContents *)contents didEnterFullscreenForOrigin:(NSURL *)origin {
  NSView *view = contents.view;
  NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
  if (_fullscreenWindow || !view.superview || !screen) return;
  _fullscreenOrigin = view.superview;
  _fullscreenOriginFrame = view.frame;
  _fullscreenWindow = [[FLXFullscreenWindow alloc] initWithContentRect:screen.frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
  _fullscreenWindow.releasedWhenClosed = NO;
  _fullscreenWindow.backgroundColor = NSColor.blackColor;
  _fullscreenWindow.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
  [_fullscreenWindow setFrame:screen.frame display:NO];
  view.frame = _fullscreenWindow.contentView.bounds;
  [_fullscreenWindow.contentView addSubview:view];
  _presentationBeforeFullscreen = NSApp.presentationOptions;
  NSApp.presentationOptions = NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
  [_fullscreenWindow makeKeyAndOrderFront:nil];
  [_fullscreenWindow makeFirstResponder:view];
  // Chrome leaves full screen on Escape before the page sees it, so a page can't keep the user in.
  __weak FLXBrowserView *weakSelf = self;
  _escapeMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    FLXBrowserView *view = weakSelf;
    if (!view || event.keyCode != 53 || event.window != view->_fullscreenWindow) return event;
    [view->_contents exitFullscreenResizingView:YES];
    return nil;
  }];
}

- (void)webContentsDidExitFullscreen:(ECWebContents *)contents {
  [self leaveFullscreenWindow];
}

- (void)leaveFullscreenWindow {
  if (!_fullscreenWindow) return;
  if (_escapeMonitor) [NSEvent removeMonitor:_escapeMonitor];
  _escapeMonitor = nil;
  NSView *view = _contents.view;
  NSView *origin = _fullscreenOrigin ?: self;
  if (view) {
    view.frame = origin == self ? self.bounds : _fullscreenOriginFrame;
    [origin addSubview:view positioned:NSWindowBelow relativeTo:nil];
  }
  NSApp.presentationOptions = _presentationBeforeFullscreen;
  [_fullscreenWindow orderOut:nil];
  _fullscreenWindow = nil;
  _fullscreenOrigin = nil;
  [self.window makeKeyAndOrderFront:nil];
  if (view) [self.window makeFirstResponder:view];
}

// The page's target among the browser-wide protocol's, found by the id its document start script
// gives it, then a session attached to it.
- (void)withSession:(void (^)(NSString *_Nullable sessionID))block {
  if (_sessionID) return block(_sessionID);
  if (!FLXDevTools.isAvailable || !_contents) return block(nil);
  if (_sessionWaiters) {
    [_sessionWaiters addObject:[block copy]];
    return;
  }
  _sessionWaiters = [NSMutableArray arrayWithObject:[block copy]];
  __weak FLXBrowserView *weakSelf = self;
  [FLXDevTools sendMethod:@"Target.getTargets" params:@{} sessionID:nil completion:^(NSDictionary *result, NSString *) {
    // Chrome counts pages outside its tab strip as "other" targets. Those showing the page's address
    // are tried first.
    FLXBrowserView *view = weakSelf;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSDictionary *info in result[@"targetInfos"]) {
      if (![info[@"type"] isEqual:@"page"] && ![info[@"type"] isEqual:@"other"]) continue;
      if ([info[@"url"] isEqual:view.currentURL]) {
        [candidates insertObject:info[@"targetId"] atIndex:0];
      } else {
        [candidates addObject:info[@"targetId"]];
      }
    }
    [weakSelf findTargetAmong:candidates];
  }];
}

- (void)findTargetAmong:(NSMutableArray<NSString *> *)candidates {
  if (candidates.count == 0) return [self finishSessionSearch:nil];
  NSString *targetID = candidates.firstObject;
  [candidates removeObjectAtIndex:0];
  __weak FLXBrowserView *weakSelf = self;
  [FLXDevTools sendMethod:@"Target.attachToTarget"
                   params:@{@"targetId": targetID, @"flatten": @YES}
                sessionID:nil
               completion:^(NSDictionary *attached, NSString *) {
    NSString *sessionID = attached[@"sessionId"];
    if (!sessionID) return [weakSelf findTargetAmong:candidates];
    [FLXDevTools sendMethod:@"Runtime.evaluate"
                     params:@{@"expression": @"globalThis[Symbol.for('flux.page')]", @"returnByValue": @YES}
                  sessionID:sessionID
                 completion:^(NSDictionary *evaluated, NSString *) {
      FLXBrowserView *view = weakSelf;
      if (!view) return;
      if ([evaluated[@"result"][@"value"] isEqual:view->_pageID]) {
        view->_targetID = targetID;
        return [view finishSessionSearch:sessionID];
      }
      [FLXDevTools sendMethod:@"Target.detachFromTarget" params:@{@"sessionId": sessionID} sessionID:nil
                   completion:^(NSDictionary *, NSString *) {}];
      [view findTargetAmong:candidates];
    }];
  }];
}

- (void)finishSessionSearch:(NSString *)sessionID {
  _sessionID = sessionID;
  NSArray *waiters = _sessionWaiters;
  _sessionWaiters = nil;
  for (void (^waiter)(NSString *) in waiters) waiter(sessionID);
}

- (void)sendDevToolsMethod:(NSString *)method
                    params:(NSDictionary<NSString *, id> *)params
                completion:(void (^)(NSDictionary<NSString *, id> *))completion {
  [self withSession:^(NSString *sessionID) {
    if (!sessionID) return completion(nil);
    [FLXDevTools sendMethod:method params:params ?: @{} sessionID:sessionID
                 completion:^(NSDictionary *result, NSString *) { completion(result); }];
  }];
}

- (void)devToolsTargetID:(void (^)(NSString *))completion {
  __weak FLXBrowserView *weakSelf = self;
  [self withSession:^(NSString *) {
    FLXBrowserView *view = weakSelf;
    completion(view ? view->_targetID : nil);
  }];
}

- (void)evaluateJavaScript:(NSString *)expression completion:(void (^)(id))completion {
  [self sendDevToolsMethod:@"Runtime.evaluate"
                    params:@{@"expression": expression, @"returnByValue": @YES}
                completion:^(NSDictionary *result) {
    completion(result[@"result"][@"value"]);
  }];
}

#pragma mark - ECWebContentsDelegate

- (void)webContentsDidUpdate:(ECWebContents *)contents {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  NSString *url = contents.URL.absoluteString;
  if (url.length && ![url isEqualToString:_currentURL]) {
    self.currentURL = url;
    if ([delegate respondsToSelector:@selector(browserView:didChangeURL:)]) [delegate browserView:self didChangeURL:url];
  }
  if (![contents.title isEqualToString:_title]) {
    self.title = contents.title;
    if ([delegate respondsToSelector:@selector(browserView:didChangeTitle:)]) [delegate browserView:self didChangeTitle:_title];
  }
  if (contents.favicon && contents.favicon != _favicon) {
    _favicon = contents.favicon;
    if ([delegate respondsToSelector:@selector(browserView:didChangeFavicon:)]) [delegate browserView:self didChangeFavicon:_favicon];
  }
  if (contents.audible != _audible) {
    _audible = contents.audible;
    if ([delegate respondsToSelector:@selector(browserView:didChangeAudible:)]) [delegate browserView:self didChangeAudible:_audible];
  }
  if ([delegate respondsToSelector:@selector(browserViewDidChangeNavigationState:)]) {
    [delegate browserViewDidChangeNavigationState:self];
  }
  if (_loading && !contents.isLoading && [delegate respondsToSelector:@selector(browserViewDidFinishLoading:)]) {
    [delegate browserViewDidFinishLoading:self];
  }
  _loading = contents.isLoading;
}

// Chrome's own context menu needs one of its browser windows, so Flux makes its own.
- (void)webContents:(ECWebContents *)contents showContextMenu:(ECContextMenu *)context {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  __weak FLXBrowserView *weakSelf = self;
  __weak ECWebContents *weakContents = contents;
  void (^add)(NSString *, void (^)(void)) = ^(NSString *title, void (^block)(void)) {
    [menu addItem:[[FLXBlockMenuItem alloc] initWithTitle:title block:block]];
  };
  void (^separate)(void) = ^{
    if (menu.numberOfItems && !menu.itemArray.lastObject.isSeparatorItem) [menu addItem:NSMenuItem.separatorItem];
  };
  void (^copyString)(NSString *) = ^(NSString *string) {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:string forType:NSPasteboardTypeString];
  };

  NSURL *link = context.linkURL;
  if (link) {
    add(NSLocalizedString(@"Open Link in New Tab", nil), ^{
      [weakSelf openPageWithURL:link disposition:ECWindowOpenDispositionNewBackgroundTab];
    });
    add(NSLocalizedString(@"Copy Link Address", nil), ^{ copyString(link.absoluteString); });
    add(NSLocalizedString(@"Save Link As…", nil), ^{ [context saveLink]; });
    separate();
  }
  NSURL *image = context.imageURL;
  if (image) {
    add(NSLocalizedString(@"Open Image in New Tab", nil), ^{
      [weakSelf openPageWithURL:image disposition:ECWindowOpenDispositionNewBackgroundTab];
    });
    add(NSLocalizedString(@"Copy Image", nil), ^{ [context copyImage]; });
    add(NSLocalizedString(@"Copy Image Address", nil), ^{ copyString(image.absoluteString); });
    add(NSLocalizedString(@"Save Image As…", nil), ^{ [context saveImage]; });
    separate();
  }
  NSString *selection = context.selectionText;
  ECEditFlags flags = context.editFlags;
  if (context.editable) {
    NSArray *edits = @[
      @[NSLocalizedString(@"Undo", nil), @(ECEditFlagCanUndo), NSStringFromSelector(@selector(undo:))],
      @[NSLocalizedString(@"Redo", nil), @(ECEditFlagCanRedo), NSStringFromSelector(@selector(redo:))],
      @"",
      @[NSLocalizedString(@"Cut", nil), @(ECEditFlagCanCut), NSStringFromSelector(@selector(cut:))],
      @[NSLocalizedString(@"Copy", nil), @(ECEditFlagCanCopy), NSStringFromSelector(@selector(copy:))],
      @[NSLocalizedString(@"Paste", nil), @(ECEditFlagCanPaste), NSStringFromSelector(@selector(paste:))],
      @[NSLocalizedString(@"Paste and Match Style", nil), @(ECEditFlagCanPaste), NSStringFromSelector(@selector(pasteAndMatchStyle:))],
      @[NSLocalizedString(@"Select All", nil), @(ECEditFlagCanSelectAll), NSStringFromSelector(@selector(selectAll:))],
    ];
    for (id edit in edits) {
      if (![edit isKindOfClass:NSArray.class]) {
        separate();
        continue;
      }
      NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:edit[0] action:NSSelectorFromString(edit[2]) keyEquivalent:@""];
      item.target = contents;
      item.enabled = (flags & [edit[1] unsignedIntegerValue]) != 0;
      [menu addItem:item];
    }
    menu.autoenablesItems = NO;
    separate();
  } else if (selection.length) {
    NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Copy", nil) action:@selector(copy:) keyEquivalent:@""];
    copy.target = contents;
    [menu addItem:copy];
  }
  if (selection.length) {
    NSString *shown = selection.length > 30 ? [[selection substringToIndex:30] stringByAppendingString:@"…"] : selection;
    add([NSString stringWithFormat:NSLocalizedString(@"Look Up “%@”", nil), shown], ^{ [context lookUp]; });
    add([NSString stringWithFormat:NSLocalizedString(@"Search Google for “%@”", nil), shown], ^{
      NSURLComponents *search = [NSURLComponents componentsWithString:@"https://www.google.com/search"];
      search.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:selection]];
      [weakSelf openPageWithURL:search.URL disposition:ECWindowOpenDispositionNewForegroundTab];
    });
    separate();
  }
  if (!link && !image && !selection.length && !context.editable) {
    NSMenuItem *back = [[FLXBlockMenuItem alloc] initWithTitle:NSLocalizedString(@"Back", nil) block:^{ [weakContents goBack]; }];
    NSMenuItem *forward = [[FLXBlockMenuItem alloc] initWithTitle:NSLocalizedString(@"Forward", nil) block:^{ [weakContents goForward]; }];
    back.enabled = self.canGoBack;
    forward.enabled = self.canGoForward;
    menu.autoenablesItems = NO;
    [menu addItem:back];
    [menu addItem:forward];
    add(NSLocalizedString(@"Reload", nil), ^{ [weakContents reload]; });
    separate();
    add(NSLocalizedString(@"Save As…", nil), ^{ [weakContents savePage]; });
    add(NSLocalizedString(@"Print…", nil), ^{ [weakContents print]; });
    add(NSLocalizedString(@"View Page Source", nil), ^{
      FLXBrowserView *view = weakSelf;
      NSURL *source = [NSURL URLWithString:[@"view-source:" stringByAppendingString:view.currentURL ?: @""]];
      if (source) [view openPageWithURL:source disposition:ECWindowOpenDispositionNewForegroundTab];
    });
    separate();
  }

  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserView:contextMenuItemsForSelectedText:)]) {
    NSArray<NSString *> *titles = [delegate browserView:self contextMenuItemsForSelectedText:selection ?: @""];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *) {
      add(title, ^{
        FLXBrowserView *view = weakSelf;
        id<FLXBrowserViewDelegate> current = view.delegate;
        if ([current respondsToSelector:@selector(browserView:didChooseContextMenuItemAtIndex:selectedText:point:)]) {
          [current browserView:view didChooseContextMenuItemAtIndex:index selectedText:selection ?: @"" point:NSEvent.mouseLocation];
        }
      });
    }];
    separate();
  }
  add(NSLocalizedString(@"Inspect", nil), ^{ [context inspect]; });

  NSView *view = contents.view;
  NSPoint point = [view convertPoint:view.window.mouseLocationOutsideOfEventStream fromView:nil];
  [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
}

- (void)openPageWithURL:(NSURL *)url disposition:(ECWindowOpenDisposition)disposition {
  if (_contents) [self webContents:_contents requestsNewWindowWithURL:url disposition:disposition];
}

// Chromium asks for a foreground tab both for a link with a target and for a ⌘⇧-click. Only the
// page's own links and window.open() come with a page Chromium created, the clicks with a URL.
static FLXOpenDisposition FluxDisposition(ECWindowOpenDisposition disposition, BOOL openedByPage) {
  switch (disposition) {
    case ECWindowOpenDispositionNewBackgroundTab: return FLXOpenDispositionBackgroundTab;
    case ECWindowOpenDispositionNewWindow: return FLXOpenDispositionShiftClick;
    case ECWindowOpenDispositionNewPopup: return FLXOpenDispositionLinkTarget;
    default: return openedByPage ? FLXOpenDispositionLinkTarget : FLXOpenDispositionForegroundTab;
  }
}

- (void)webContents:(ECWebContents *)contents
    requestsNewWindowWithURL:(NSURL *)url
                 disposition:(ECWindowOpenDisposition)disposition {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(browserView:didOpenPage:disposition:)]) return;
  FLXBrowserView *page = [[FLXBrowserView alloc] initWithURL:url.absoluteString profile:_profile];
  [delegate browserView:self didOpenPage:page disposition:FluxDisposition(disposition, NO)];
}

- (void)webContents:(ECWebContents *)contents
    didOpenWebContents:(ECWebContents *)opened
                   URL:(NSURL *)url
           disposition:(ECWindowOpenDisposition)disposition
         modifierFlags:(NSEventModifierFlags)modifierFlags {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(browserView:didOpenPage:disposition:)]) return;
  FLXBrowserView *page = [[FLXBrowserView alloc] initWithOpenedContents:opened URL:url.absoluteString profile:_profile];
  [delegate browserView:self didOpenPage:page disposition:FluxDisposition(disposition, YES)];
}

- (void)webContents:(ECWebContents *)contents
    requestsPermissions:(NSArray<NSString *> *)permissions
              forOrigin:(NSURL *)origin
      completionHandler:(void (^)(BOOL))completionHandler {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(browserView:didRequestPermission:)]) return completionHandler(NO);
  FLXPermission flags = 0;
  for (NSString *permission in permissions) flags |= PermissionForKey(permission);
  NSString *originString = origin.absoluteString;
  if (![originString hasSuffix:@"/"]) originString = [originString stringByAppendingString:@"/"];
  FLXPermissionRequest *request = [[FLXPermissionRequest alloc] initWithOrigin:originString
                                                                    permissions:flags
                                                                     completion:completionHandler];
  [delegate browserView:self didRequestPermission:request];
}

- (void)webContents:(ECWebContents *)contents
    runJavaScriptDialog:(ECJavaScriptDialogType)type
                message:(NSString *)message
            defaultText:(NSString *)defaultText
      completionHandler:(void (^)(BOOL, NSString *))completionHandler {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = type == ECJavaScriptDialogTypeBeforeUnload ? @"Leave this page?" : (contents.URL.host ?: @"");
  alert.informativeText = message;
  [alert addButtonWithTitle:@"OK"];
  if (type != ECJavaScriptDialogTypeAlert) [alert addButtonWithTitle:@"Cancel"];
  NSTextField *field = nil;
  if (type == ECJavaScriptDialogTypePrompt) {
    field = [NSTextField textFieldWithString:defaultText];
    field.frame = NSMakeRect(0, 0, 260, 22);
    alert.accessoryView = field;
  }
  if (!self.window) return completionHandler(NO, @"");
  [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    completionHandler(response == NSAlertFirstButtonReturn, field.stringValue ?: @"");
  }];
}

#pragma mark - Offers to save and device choosers

- (void)offerToSave:(FLXSaveOffer *)offer orAnswer:(void (^)(void))unanswered {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(browserView:didOfferToSave:)]) return unanswered();
  [delegate browserView:self didOfferToSave:offer];
}

- (void)webContents:(ECWebContents *)contents
     offersToSaveCard:(ECCardOffer *)card
    completionHandler:(void (^)(ECCardOfferAnswer))completionHandler {
  NSString *line = [NSString stringWithFormat:@"%@ •••• %@", card.network, card.lastFourDigits];
  FLXSaveOffer *offer = [[FLXSaveOffer alloc] initWithKind:FLXSaveOfferKindCard update:card.isSecurityCodeOnly
                                                     lines:@[ line ]
                                                    answer:^(FLXSaveOfferAnswer answer) {
    completionHandler(answer == FLXSaveOfferAnswerSave ? ECCardOfferAnswerSave
                      : answer == FLXSaveOfferAnswerDecline ? ECCardOfferAnswerDecline : ECCardOfferAnswerIgnore);
  }];
  [self offerToSave:offer orAnswer:^{ completionHandler(ECCardOfferAnswerIgnore); }];
}

- (void)webContents:(ECWebContents *)contents
    offersToSaveAddress:(ECAddressOffer *)address
      completionHandler:(void (^)(ECAddressOfferAnswer))completionHandler {
  FLXSaveOffer *offer = [[FLXSaveOffer alloc] initWithKind:FLXSaveOfferKindAddress update:address.isUpdate
                                                     lines:AddressLines(address.address)
                                                    answer:^(FLXSaveOfferAnswer answer) {
    completionHandler(answer == FLXSaveOfferAnswerSave ? ECAddressOfferAnswerSave
                      : answer == FLXSaveOfferAnswerDecline ? ECAddressOfferAnswerDecline : ECAddressOfferAnswerIgnore);
  }];
  [self offerToSave:offer orAnswer:^{ completionHandler(ECAddressOfferAnswerIgnore); }];
}

- (void)webContents:(ECWebContents *)contents
     offersToSaveIban:(ECIbanOffer *)iban
    completionHandler:(void (^)(ECIbanOfferAnswer, NSString *))completionHandler {
  NSArray<NSString *> *lines = iban.nickname.length ? @[ iban.nickname, iban.maskedValue ] : @[ iban.maskedValue ];
  FLXSaveOffer *offer = [[FLXSaveOffer alloc] initWithKind:FLXSaveOfferKindIban update:NO
                                                     lines:lines
                                                    answer:^(FLXSaveOfferAnswer answer) {
    completionHandler(answer == FLXSaveOfferAnswerSave ? ECIbanOfferAnswerSave
                      : answer == FLXSaveOfferAnswerDecline ? ECIbanOfferAnswerDecline : ECIbanOfferAnswerIgnore, nil);
  }];
  [self offerToSave:offer orAnswer:^{ completionHandler(ECIbanOfferAnswerIgnore, nil); }];
}

- (void)webContents:(ECWebContents *)contents showChooser:(ECChooser *)chooser {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(browserView:didRequestDevice:)]) return [chooser cancel];
  [delegate browserView:self didRequestDevice:[[FLXDeviceChooser alloc] initWithChooser:chooser]];
}

// getDisplayMedia(): a screen or a window, then macOS's picker says which one.
- (void)webContents:(ECWebContents *)contents
    requestsDisplayCaptureFromOrigin:(NSURL *)origin
                            surfaces:(ECDisplaySurfaces)surfaces
                   completionHandler:(void (^)(ECDisplaySurface))completionHandler {
  NSWindow *window = self.window;
  if (!window) return completionHandler(ECDisplaySurfaceNone);
  BOOL screen = (surfaces & ECDisplaySurfacesScreen) != 0;
  BOOL windows = (surfaces & ECDisplaySurfacesWindow) != 0;
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"Share your screen with %@?", nil),
                                                 origin.host ?: origin.absoluteString];
  alert.informativeText = NSLocalizedString(@"macOS then asks which one to share.", nil);
  NSMutableArray<NSNumber *> *answers = [NSMutableArray array];
  if (screen) {
    [alert addButtonWithTitle:NSLocalizedString(@"Entire Screen", nil)];
    [answers addObject:@(ECDisplaySurfaceScreen)];
  }
  if (windows) {
    [alert addButtonWithTitle:NSLocalizedString(@"A Window", nil)];
    [answers addObject:@(ECDisplaySurfaceWindow)];
  }
  [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    NSInteger index = response - NSAlertFirstButtonReturn;
    completionHandler(index >= 0 && index < (NSInteger)answers.count
                          ? (ECDisplaySurface)answers[index].integerValue
                          : ECDisplaySurfaceNone);
  }];
}

// A site or a proxy asking for a username and a password, in a sheet as Safari does.
- (void)webContents:(ECWebContents *)contents
    requestsCredentials:(ECAuthChallenge *)challenge
      completionHandler:(void (^)(NSString *, NSString *))completionHandler {
  NSWindow *window = self.window;
  if (!window) return completionHandler(nil, nil);
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = challenge.isProxy
      ? [NSString stringWithFormat:NSLocalizedString(@"Sign in to the proxy %@", nil), challenge.host]
      : [NSString stringWithFormat:NSLocalizedString(@"Sign in to %@", nil), challenge.host];
  alert.informativeText = challenge.warning
      ? [NSString stringWithFormat:@"%@\n\n%@", challenge.message, challenge.warning]
      : challenge.message;
  [alert addButtonWithTitle:NSLocalizedString(@"Sign In", nil)];
  [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

  NSTextField *username = [NSTextField textFieldWithString:@""];
  username.placeholderString = NSLocalizedString(@"Username", nil);
  username.contentType = NSTextContentTypeUsername;
  NSSecureTextField *password = [[NSSecureTextField alloc] init];
  password.placeholderString = NSLocalizedString(@"Password", nil);
  password.contentType = NSTextContentTypePassword;
  NSStackView *fields = [NSStackView stackViewWithViews:@[ username, password ]];
  fields.orientation = NSUserInterfaceLayoutOrientationVertical;
  fields.spacing = 8;
  fields.frame = NSMakeRect(0, 0, 260, 52);
  for (NSView *field in @[ username, password ]) {
    [field.widthAnchor constraintEqualToConstant:260].active = YES;
  }
  alert.accessoryView = fields;
  alert.window.initialFirstResponder = username;

  challenge.savedLoginHandler = ^(NSString *savedUsername, NSString *savedPassword) {
    if (username.stringValue.length) return;
    username.stringValue = savedUsername;
    password.stringValue = savedPassword;
  };
  __block BOOL answered = NO;
  __weak NSAlert *weakAlert = alert;
  __weak NSWindow *weakWindow = window;
  challenge.dismissHandler = ^{
    NSAlert *shown = weakAlert;
    if (answered || !shown) return;
    answered = YES;
    [weakWindow endSheet:shown.window];
  };
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    if (answered) return;
    answered = YES;
    if (response == NSAlertFirstButtonReturn) {
      completionHandler(username.stringValue, password.stringValue);
    } else {
      completionHandler(nil, nil);
    }
  }];
}

- (void)webContents:(ECWebContents *)contents
    runFileChooserWithAcceptTypes:(NSArray<NSString *> *)acceptTypes
                   allowsMultiple:(BOOL)allowsMultiple
                        directory:(BOOL)directory
                completionHandler:(void (^)(NSArray<NSURL *> *))completionHandler {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.allowsMultipleSelection = allowsMultiple;
  panel.canChooseDirectories = directory;
  panel.canChooseFiles = !directory;
  void (^done)(NSModalResponse) = ^(NSModalResponse response) {
    completionHandler(response == NSModalResponseOK ? panel.URLs : nil);
  };
  if (self.window) {
    [panel beginSheetModalForWindow:self.window completionHandler:done];
  } else {
    done([panel runModal]);
  }
}

- (void)webContents:(ECWebContents *)contents didFindMatches:(NSInteger)matches activeMatch:(NSInteger)activeMatch {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserView:didFindMatches:activeMatch:)]) {
    [delegate browserView:self didFindMatches:matches activeMatch:activeMatch];
  }
}

- (void)webContentsDidRequestClose:(ECWebContents *)contents {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  // A new tab that only started a download has committed nothing.
  if (!contents.URL && [delegate respondsToSelector:@selector(browserViewDidOpenOnlyDownload:)]) {
    [delegate browserViewDidOpenOnlyDownload:self];
  } else if ([delegate respondsToSelector:@selector(browserViewDidClose:)]) {
    [delegate browserViewDidClose:self];
  }
}

- (void)webContentsDidRequestActivation:(ECWebContents *)contents {
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserViewDidRequestShow:)]) [delegate browserViewDidRequestShow:self];
}

- (void)webContents:(ECWebContents *)contents didCommitNavigationIsHistory:(BOOL)isHistory {
  [_mediaStates removeAllObjects];
  [self updateMedia];
  [self webContentsDidUpdate:contents];
}

- (void)webContents:(ECWebContents *)contents
    didReceiveMessage:(NSString *)message
           fromObject:(NSString *)name
               origin:(NSURL *)origin
            mainFrame:(BOOL)mainFrame {
  if (![name isEqualToString:kMediaObject]) return;
  NSString *frame = [NSString stringWithFormat:@"%d %@", mainFrame, origin.absoluteString ?: @""];
  _mediaStates[frame] = message;
  [self updateMedia];
}

// The page's media is the frame that last reported playing, or else any frame that played.
- (void)updateMedia {
  NSString *shown = nil;
  for (NSString *state in _mediaStates.allValues) {
    if (!shown || [state containsString:@"\"playing\":true"]) shown = state;
  }
  if ((shown ?: @"").hash == (_shownMedia ?: @"").hash && [shown ?: @"" isEqualToString:_shownMedia ?: @""]) return;
  _shownMedia = shown;
  id<FLXBrowserViewDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(browserView:didChangeMedia:)]) return;
  NSData *data = [shown dataUsingEncoding:NSUTF8StringEncoding];
  id media = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  [delegate browserView:self didChangeMedia:[media isKindOfClass:NSDictionary.class] ? media : nil];
}

- (void)webContents:(ECWebContents *)contents
    requestsInstallOfExtensionNamed:(NSString *)name
                               icon:(NSImage *)icon
                        permissions:(NSArray<NSString *> *)permissions
                  completionHandler:(void (^)(BOOL))completionHandler {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = [NSString stringWithFormat:@"Add “%@”?", name];
  alert.informativeText = permissions.count ? [@"It can:\n" stringByAppendingString:[permissions componentsJoinedByString:@"\n"]] : @"";
  if (icon) alert.icon = icon;
  [alert addButtonWithTitle:@"Add Extension"];
  [alert addButtonWithTitle:@"Cancel"];
  if (!self.window) return completionHandler(NO);
  [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    completionHandler(response == NSAlertFirstButtonReturn);
  }];
}

- (void)webContents:(ECWebContents *)contents
    requestsOpeningURL:(NSURL *)url
    inApplicationNamed:(NSString *)appName
            fromOrigin:(NSURL *)origin
     completionHandler:(void (^)(BOOL))completionHandler {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = [NSString stringWithFormat:@"Open “%@”?", appName];
  [alert addButtonWithTitle:@"Open"];
  [alert addButtonWithTitle:@"Cancel"];
  if (!self.window) return completionHandler(NO);
  [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    completionHandler(response == NSAlertFirstButtonReturn);
  }];
}

@end
