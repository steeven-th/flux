#include <map>
#include <set>
#include <string>

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

// What the frame plays, for the mini player, and the commands it gets back. Sites give their
// previous and next track actions to navigator.mediaSession, which offers no way to call them from
// outside, so the script keeps them as the site sets them. Without them, play, pause and volume go
// to the media elements. Nothing is reported until something has played in the frame.
//
// Like Chromium's own media sessions, which CEF doesn't expose, a media element only counts once it
// plays sound for at least 5 seconds of content: muted autoplay videos, notification sounds and
// calls stay out of the mini player.
constexpr char kMediaWatcher[] = R"(
((report) => {
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
  // Chromium counts the audio it decodes, which stays at zero for a video without a sound track.
  const isAudible = (element) => !element.muted && element.volume > 0
    && (element.webkitAudioDecodedByteCount ?? 1) > 0;
  const note = (element) => {
    if (!elements.has(element) && (element.paused || !isContent(element) || !isAudible(element))) return;
    elements.delete(element);
    elements.add(element);
    if (!element.paused) hasPlayed = true;
    send();
  };

  // The MediaSession global only shows up after this script runs, but navigator.mediaSession is
  // already there.
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

  // timeupdate catches the decoded audio, which only shows once playback has started.
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

  const run = (action, fallback) => {
    const handler = handlers.get(action);
    if (!handler) return fallback?.();
    try { handler({ action }); } catch {}
  };
  return (command, value) => {
    switch (command) {
      case 'play': run('play', () => latest()?.play()); break;
      case 'pause': run('pause', () => elements.forEach((element) => element.pause())); break;
      case 'previous': run('previoustrack'); break;
      case 'next': run('nexttrack'); break;
      case 'volume': elements.forEach((element) => { element.volume = value; }); break;
    }
    send();
  };
})
)";

constexpr char kMediaMessage[] = "FluxMedia";
constexpr char kMediaCommandMessage[] = "FluxMediaCommand";

// Sends the script's single argument, whether the frame plays sound or what it plays, to the
// browser process.
class FrameReporter : public CefV8Handler {
 public:
  FrameReporter(CefRefPtr<CefFrame> frame, const char* message) : frame_(frame), message_(message) {}

  bool Execute(const CefString& name, CefRefPtr<CefV8Value> object, const CefV8ValueList& arguments,
               CefRefPtr<CefV8Value>& retval, CefString& exception) override {
    if (arguments.empty() || !frame_->IsValid()) return true;
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(message_);
    if (arguments[0]->IsBool()) {
      message->GetArgumentList()->SetBool(0, arguments[0]->GetBoolValue());
    } else {
      message->GetArgumentList()->SetString(0, arguments[0]->GetStringValue());
    }
    frame_->SendProcessMessage(PID_BROWSER, message);
    return true;
  }

 private:
  CefRefPtr<CefFrame> frame_;
  std::string message_;
  IMPLEMENT_REFCOUNTING(FrameReporter);
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
    // Extensions' content scripts get contexts of their own in the frame, which see the page's
    // media events but not its objects.
    CefRefPtr<CefV8Context> page_context = frame->GetV8Context();
    if (!page_context || !context->IsSame(page_context)) return;
    Watch(kAudioWatcher, kAudioMessage, frame, context);
    std::string id = frame->GetIdentifier().ToString();
    page_contexts_[id] = context;
    CefRefPtr<CefV8Value> control = Watch(kMediaWatcher, kMediaMessage, frame, context);
    if (control && control->IsFunction()) media_controls_[id] = control;
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
    std::string id = frame->GetIdentifier().ToString();
    auto page_context = page_contexts_.find(id);
    if (page_context == page_contexts_.end() || !context->IsSame(page_context->second)) return;
    page_contexts_.erase(page_context);
    media_controls_.erase(id);
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kAudioMessage);
    message->GetArgumentList()->SetBool(0, false);
    frame->SendProcessMessage(PID_BROWSER, message);
    CefRefPtr<CefProcessMessage> media = CefProcessMessage::Create(kMediaMessage);
    media->GetArgumentList()->SetString(0, "");
    frame->SendProcessMessage(PID_BROWSER, media);
  }

  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override {
    if (message->GetName() != kMediaCommandMessage) return false;
    auto control = media_controls_.find(frame->GetIdentifier().ToString());
    CefRefPtr<CefV8Context> context = frame->GetV8Context();
    if (control == media_controls_.end() || !context) return true;
    CefRefPtr<CefListValue> arguments = message->GetArgumentList();
    CefV8ValueList values{CefV8Value::CreateString(arguments->GetString(0)),
                          CefV8Value::CreateDouble(arguments->GetDouble(1))};
    control->second->ExecuteFunctionWithContext(context, nullptr, values);
    return true;
  }

 private:
  // The reporting function is handed to the script rather than put on the page's globals.
  // Returns what the script returns.
  static CefRefPtr<CefV8Value> Watch(const char* script, const char* message, CefRefPtr<CefFrame> frame,
                                     CefRefPtr<CefV8Context> context) {
    CefRefPtr<CefV8Value> watcher;
    CefRefPtr<CefV8Exception> exception;
    if (!context->Eval(script, CefString(), 0, watcher, exception) || !watcher->IsFunction()) return nullptr;
    CefV8ValueList arguments{CefV8Value::CreateFunction("report", new FrameReporter(frame, message))};
    return watcher->ExecuteFunctionWithContext(context, nullptr, arguments);
  }

  std::set<int> popup_browsers_;
  /// The page's own context in each frame, and the media script's command function there, by
  /// frame identifier.
  std::map<std::string, CefRefPtr<CefV8Context>> page_contexts_;
  std::map<std::string, CefRefPtr<CefV8Value>> media_controls_;

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
