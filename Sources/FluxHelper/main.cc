#include <set>

#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

// Flux shows extension popups and side panels in a page of its own rather than in Chrome's, so
// Chromium treats them as tabs. Some extensions check for that: Bitwarden only fixes its width
// when chrome.tabs.getCurrent() finds no tab, and some side panels refuse to run in a tab. In a
// real popup or side panel it returns undefined, so it does here too.
//
// Chromium adds the extension APIs after this script runs, to the existing `chrome` object if
// there is one. So the script provides that object, and patches it the first time the page reads
// `chrome`, by when the APIs are there.
constexpr char kPopupShim[] = R"(
(() => {
  const chromeObject = {};
  const getCurrent = (callback) => {
    if (typeof callback === 'function') { callback(undefined); return; }
    return Promise.resolve(undefined);
  };
  Object.defineProperty(globalThis, 'chrome', {
    configurable: true,
    get() {
      const tabs = chromeObject.tabs;
      if (tabs) {
        Object.defineProperty(tabs, 'getCurrent', { value: getCurrent, configurable: true, writable: true });
        Object.defineProperty(globalThis, 'chrome', { value: chromeObject, configurable: true, writable: true });
      }
      return chromeObject;
    },
  });
})();
)";

// Chromium knows when a tab plays sound but CEF doesn't say, so each frame tells Flux itself. Media
// events don't bubble, so they are caught on their way down to elements in the page. Players often
// keep their element out of the page, so play() notes those too. Web Audio isn't followed.
constexpr char kAudioWatcher[] = R"(
((report) => {
  const audible = new Set();
  let wasAudible = false;
  const check = (media) => {
    if (!media.paused && !media.ended && !media.muted && media.volume > 0) audible.add(media);
    else audible.delete(media);
    if ((audible.size > 0) !== wasAudible) {
      wasAudible = audible.size > 0;
      report(wasAudible);
    }
  };
  const types = ['playing', 'pause', 'ended', 'emptied', 'volumechange'];
  for (const type of types) {
    document.addEventListener(type, (event) => {
      if (event.target instanceof HTMLMediaElement) check(event.target);
    }, true);
  }
  const watched = new WeakSet();
  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () {
    if (!this.isConnected && !watched.has(this)) {
      watched.add(this);
      for (const type of types) this.addEventListener(type, () => check(this));
    }
    return play.apply(this, arguments);
  };
})
)";

constexpr char kAudioMessage[] = "FluxAudio";

// Sends whether the frame plays sound to the browser process.
class AudioReporter : public CefV8Handler {
 public:
  explicit AudioReporter(CefRefPtr<CefFrame> frame) : frame_(frame) {}

  bool Execute(const CefString& name, CefRefPtr<CefV8Value> object, const CefV8ValueList& arguments,
               CefRefPtr<CefV8Value>& retval, CefString& exception) override {
    if (arguments.empty() || !frame_->IsValid()) return true;
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kAudioMessage);
    message->GetArgumentList()->SetBool(0, arguments[0]->GetBoolValue());
    frame_->SendProcessMessage(PID_BROWSER, message);
    return true;
  }

 private:
  CefRefPtr<CefFrame> frame_;
  IMPLEMENT_REFCOUNTING(AudioReporter);
};

class RendererApp : public CefApp, public CefRenderProcessHandler {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }

  void OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> extra_info) override {
    if (extra_info && extra_info->GetBool("extension_popup")) {
      popup_browsers_.insert(browser->GetIdentifier());
    }
  }

  void OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) override {
    popup_browsers_.erase(browser->GetIdentifier());
  }

  void OnContextCreated(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefV8Context> context) override {
    WatchAudio(frame, context);
    if (!popup_browsers_.count(browser->GetIdentifier()) || !frame->IsMain()) return;
    if (frame->GetURL().ToString().rfind("chrome-extension://", 0) != 0) return;
    CefRefPtr<CefV8Value> result;
    CefRefPtr<CefV8Exception> exception;
    context->Eval(kPopupShim, CefString(), 0, result, exception);
  }

  // A frame going away no longer plays anything.
  void OnContextReleased(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefFrame> frame,
                         CefRefPtr<CefV8Context> context) override {
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kAudioMessage);
    message->GetArgumentList()->SetBool(0, false);
    frame->SendProcessMessage(PID_BROWSER, message);
  }

 private:
  // The reporting function is handed to the script rather than put on the page's globals.
  static void WatchAudio(CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) {
    CefRefPtr<CefV8Value> watcher;
    CefRefPtr<CefV8Exception> exception;
    if (!context->Eval(kAudioWatcher, CefString(), 0, watcher, exception) || !watcher->IsFunction()) return;
    CefV8ValueList arguments{CefV8Value::CreateFunction("report", new AudioReporter(frame))};
    watcher->ExecuteFunctionWithContext(context, nullptr, arguments);
  }

  std::set<int> popup_browsers_;

  IMPLEMENT_REFCOUNTING(RendererApp);
};

}  // namespace

// Entry point of every Chromium subprocess (renderer, GPU, utility...).
int main(int argc, char* argv[]) {
  // The sandbox has to be entered before the framework is loaded.
  CefScopedSandboxContext sandbox_context;
  if (!sandbox_context.Initialize(argc, argv)) {
    return 1;
  }

  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  return CefExecuteProcess(main_args, new RendererApp(), nullptr);
}
