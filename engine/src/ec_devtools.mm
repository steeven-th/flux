#import "engine_core/ec_web_contents_private.h"

#include <memory>
#include <string>

#include "base/strings/escape.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/devtools/chrome_devtools_manager_delegate.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_ui_bindings.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/webui/devtools/devtools_ui.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "extensions/browser/view_type_utils.h"
#include "extensions/common/mojom/view_type.mojom.h"
#include "ui/gfx/geometry/rect.h"

@interface ECDevTools ()
- (void)setInspectedPageBounds:(const gfx::Rect&)bounds;
- (void)activate;
- (void)frontendDidAskToClose;
- (void)frontendDidLoad;
- (void)frontendDidSetDocked;
- (void)openURL:(const GURL&)url;
@end

namespace {

const char kFrontendURL[] = "devtools://devtools/bundled/devtools_app.html";

// The frontend's host, as Chrome's DevToolsWindow is for its docked
// DevTools. The bindings own it.
class BindingsDelegate : public DevToolsUIBindings::Delegate {
 public:
  BindingsDelegate(ECDevTools* owner, content::WebContents* inspected)
      : owner_(owner), inspected_(inspected->GetWeakPtr()) {}

  content::WebContents* GetInspectedWebContents() override {
    return inspected_.get();
  }
  void ActivateWindow() override { [owner_ activate]; }
  void CloseWindow() override { [owner_ frontendDidAskToClose]; }
  // A worker or another target, from the frontend's lists: Chrome's own
  // window, as there is no page to dock it next to.
  void Inspect(scoped_refptr<content::DevToolsAgentHost> host) override {
    DevToolsWindow::OpenDevToolsWindowWithBundledFrontend(
        host, nullptr, DevToolsOpenedByAction::kUnknown);
  }
  void SetInspectedPageBounds(const gfx::Rect& rect) override {
    [owner_ setInspectedPageBounds:rect];
  }
  void InspectElementCompleted() override {}
  // DevTools stay docked in the embedder's window. The first call also tells
  // the frontend is ready, as for Chrome's DevToolsWindow.
  void SetIsDocked(bool is_docked) override { [owner_ frontendDidSetDocked]; }
  void OpenInNewTab(const std::string& url) override {
    [owner_ openURL:GURL(url)];
  }
  void OpenSearchResultsInNewTab(const std::string& query) override {
    [owner_ openURL:GURL("https://www.google.com/search?q=" +
                         base::EscapeQueryParamValue(query, true))];
  }
  void SetWhitelistedShortcuts(const std::string& message) override {}
  void SetEyeDropperActive(bool active) override {}
  void OpenNodeFrontend() override {}
  void InspectedContentsClosing() override { [owner_ frontendDidAskToClose]; }
  void OnLoadCompleted() override { [owner_ frontendDidLoad]; }
  void ReadyForTest() override {}
  void ConnectionReady() override {}
  void SetOpenNewWindowForPopups(bool value) override {}
  infobars::ContentInfoBarManager* GetInfoBarManager() override {
    return nullptr;
  }
  void RenderProcessGone(bool crashed) override {}
  void ShowCertificateViewer(const std::string& cert_chain) override {}
  int GetDockStateForLogging() override { return 0; }
  int GetOpenedByForLogging() override { return 0; }
  int GetClosedByForLogging() override { return 0; }

 private:
  __weak ECDevTools* owner_;
  base::WeakPtr<content::WebContents> inspected_;
};

// The frontend's web contents: links it opens become the shell's new tabs,
// and shortcuts it leaves go to the shell's main menu.
class FrontendDelegate : public content::WebContentsDelegate {
 public:
  explicit FrontendDelegate(ECDevTools* owner) : owner_(owner) {}

  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>
          navigation_handle_callback) override {
    // The frontend reloads itself with the current tab disposition.
    if (params.disposition == WindowOpenDisposition::CURRENT_TAB) {
      source->GetController().LoadURLWithParams(
          content::NavigationController::LoadURLParams(params));
      return source;
    }
    [owner_ openURL:params.url];
    return nullptr;
  }

  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override {
    return event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
           [NSApp.mainMenu performKeyEquivalent:event.os_event.Get()];
  }

  void ActivateContents(content::WebContents* contents) override {
    [owner_ activate];
  }

 private:
  __weak ECDevTools* owner_;
};

std::string PanelFor(const DevToolsToggleAction& action) {
  switch (action.type()) {
    case DevToolsToggleAction::kInspect:
    case DevToolsToggleAction::kShowElementsPanel:
      return "elements";
    case DevToolsToggleAction::kShowConsolePanel:
      return "console";
    case DevToolsToggleAction::kPauseInDebugger:
      return "sources";
    default:
      return std::string();
  }
}

// Every way of opening DevTools for one of EngineCore's pages lands here:
// showDevTools, showConsole, inspectElement, Chrome's context menu and
// shortcuts.
bool ToggleDevTools(content::WebContents* inspected,
                    bool force_open,
                    const DevToolsToggleAction& action) {
  ECWebContents* owner = [ECWebContents fromContents:inspected];
  if (!owner || ![owner.delegate respondsToSelector:@selector
                                 (webContents:didOpenDevTools:)]) {
    return false;
  }
  [owner toggleDevToolsForcingOpen:force_open action:action];
  return true;
}

}  // namespace

void RegisterDevToolsHost() {
  DevToolsWindow::SetEmbedderToggleCallback(
      base::BindRepeating(&ToggleDevTools));
  ChromeDevToolsManagerDelegate::SetIsEmbedderPageCallback(
      base::BindRepeating([](content::WebContents* contents) {
        return [ECWebContents fromContents:contents] != nil;
      }));
}

@implementation ECDevTools {
  __weak ECWebContents* _inspected;
  std::unique_ptr<content::WebContents> _frontend;
  std::unique_ptr<FrontendDelegate> _frontendDelegate;
  std::unique_ptr<DevToolsToggleAction> _pendingAction;
  NSString* _pendingPanel;
  BOOL _onLoadFired;
  BOOL _dockedSet;
  BOOL _loaded;
  NSView* _view;
}

@synthesize delegate = _delegate;
@synthesize inspectedPageBounds = _inspectedPageBounds;

- (instancetype)initWithInspectedWebContents:(ECWebContents*)inspected
                                      action:(const DevToolsToggleAction&)action {
  content::WebContents* inspectedContents = inspected.contents;
  if (!inspectedContents || !(self = [super init])) {
    return nil;
  }
  _inspected = inspected;
  Profile* profile =
      Profile::FromBrowserContext(inspectedContents->GetBrowserContext());
  _frontend = content::WebContents::Create(
      content::WebContents::CreateParams(profile));
  // DevTools zoom their own page.
  zoom::ZoomController::CreateForWebContents(_frontend.get());
  zoom::ZoomController::FromWebContents(_frontend.get())
      ->SetShowsNotificationBubble(false);
  extensions::SetViewType(_frontend.get(),
                          extensions::mojom::ViewType::kDeveloperTools);
  // can_dock turns on what only docked DevTools have, device mode among
  // them.
  std::string url = std::string(kFrontendURL) +
                    "?remoteBase=" + DevToolsUI::GetRemoteBaseURL().spec() +
                    "&targetType=tab&can_dock=true";
  std::string panel = PanelFor(action);
  if (!panel.empty()) {
    url += "&panel=" + panel;
  }
  _frontend->GetController().LoadURL(
      DevToolsUIBindings::SanitizeFrontendURL(GURL(url)), content::Referrer(),
      ui::PAGE_TRANSITION_AUTO_TOPLEVEL, std::string());
  DevToolsUIBindings* bindings =
      DevToolsUIBindings::ForWebContents(_frontend.get());
  if (!bindings) {
    return nil;
  }
  _frontendDelegate = std::make_unique<FrontendDelegate>(self);
  _frontend->SetDelegate(_frontendDelegate.get());
  bindings->SetDelegate(new BindingsDelegate(self, inspectedContents));
  bindings->AttachTo(
      content::DevToolsAgentHost::GetOrCreateForTab(inspectedContents));
  _pendingAction = std::make_unique<DevToolsToggleAction>(action);
  _view = _frontend->GetNativeView().GetNativeNSView();
  return self;
}

- (void)dealloc {
  [self close];
}

- (NSView*)view {
  return _view;
}

- (void)close {
  if (!_frontend) {
    return;
  }
  [_view removeFromSuperview];
  _frontend->SetDelegate(nullptr);
  // Takes the bindings and their delegate with it.
  _frontend.reset();
  _frontendDelegate.reset();
}

- (void)performAction:(const DevToolsToggleAction&)action {
  if (!_loaded) {
    _pendingAction = std::make_unique<DevToolsToggleAction>(action);
    return;
  }
  DevToolsUIBindings* bindings =
      _frontend ? DevToolsUIBindings::ForWebContents(_frontend.get()) : nullptr;
  if (!bindings) {
    return;
  }
  std::string panel = PanelFor(action);
  if (action.type() == DevToolsToggleAction::kInspect) {
    bindings->CallClientMethod("DevToolsAPI", "enterInspectElementMode");
  } else if (!panel.empty()) {
    bindings->CallClientMethod("DevToolsAPI", "showPanel", base::Value(panel));
  } else if (action.type() == DevToolsToggleAction::kReveal) {
    const DevToolsToggleAction::RevealParams* params = action.params();
    bindings->CallClientMethod(
        "DevToolsAPI", "revealSourceLine", base::Value(params->url),
        base::Value(static_cast<int>(params->line_number)),
        base::Value(static_cast<int>(params->column_number)));
  }
}

- (void)showPanel:(NSString*)panel {
  if (!_loaded) {
    _pendingPanel = [panel copy];
    return;
  }
  DevToolsUIBindings* bindings =
      _frontend ? DevToolsUIBindings::ForWebContents(_frontend.get()) : nullptr;
  if (bindings) {
    bindings->CallClientMethod("DevToolsAPI", "showPanel",
                               base::Value(base::SysNSStringToUTF8(panel)));
  }
}

// The document loads before the frontend's panels exist, and a panel or an
// action asked for then is lost. The frontend sets whether it is docked once
// it is ready, so Chrome's DevToolsWindow waits for both, and so does this.
- (void)frontendDidLoad {
  _onLoadFired = YES;
  [self frontendMayBeReady];
}

- (void)frontendDidSetDocked {
  _dockedSet = YES;
  [self frontendMayBeReady];
}

- (void)frontendMayBeReady {
  if (_loaded || !_onLoadFired || !_dockedSet) {
    return;
  }
  _loaded = YES;
  if (_pendingPanel) {
    [self showPanel:_pendingPanel];
    _pendingPanel = nil;
  }
  if (!_pendingAction) {
    return;
  }
  std::unique_ptr<DevToolsToggleAction> action = std::move(_pendingAction);
  // The panel was in the frontend's URL.
  if (action->type() == DevToolsToggleAction::kInspect ||
      action->type() == DevToolsToggleAction::kReveal) {
    [self performAction:*action];
  }
}

- (void)setInspectedPageBounds:(const gfx::Rect&)bounds {
  _inspectedPageBounds =
      NSMakeRect(bounds.x(), bounds.y(), bounds.width(), bounds.height());
  [_delegate devTools:self didSetInspectedPageBounds:_inspectedPageBounds];
}

- (void)activate {
  if (_frontend) {
    _frontend->Focus();
  }
}

// The bindings ask from inside their own calls, which closing would
// destroy, so the page closes its DevTools on a later turn.
- (void)frontendDidAskToClose {
  __weak ECWebContents* inspected = _inspected;
  dispatch_async(dispatch_get_main_queue(), ^{
    [inspected closeDevTools];
  });
}

- (void)openURL:(const GURL&)url {
  [_inspected requestNewWindowWithURL:url
                          disposition:WindowOpenDisposition::NEW_FOREGROUND_TAB
                          userGesture:YES];
}

@end
