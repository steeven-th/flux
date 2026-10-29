#include <set>

#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

// Flux shows extension popups in a page of its own rather than in Chrome's popup, so Chromium
// treats them as tabs. Some extensions check for that, Bitwarden for one only fixes its width when
// chrome.tabs.getCurrent() finds no tab. In a real popup it returns undefined, so it does here too.
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
    if (!popup_browsers_.count(browser->GetIdentifier()) || !frame->IsMain()) return;
    if (frame->GetURL().ToString().rfind("chrome-extension://", 0) != 0) return;
    CefRefPtr<CefV8Value> result;
    CefRefPtr<CefV8Exception> exception;
    context->Eval(kPopupShim, CefString(), 0, result, exception);
  }

 private:
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
