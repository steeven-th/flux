import AppKit
import Observation

@MainActor
@Observable
final class Tab: NSObject, Identifiable {
    let id: UUID
    let spaceID: UUID
    private(set) var url: String
    private(set) var title: String
    private(set) var favicon: NSImage?
    private(set) var isLoaded = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// The page's DevTools while open, shown next to it.
    private(set) var devTools: FLXBrowserView?
    /// What the responsive mode shows the page as, while it is on.
    private(set) var emulation: Emulation?
    private(set) var translation: PageTranslation?
    /// While translations are being put in the page.
    private(set) var isTranslating = false
    /// Detected when the page has loaded.
    private(set) var pageLanguage: Locale.Language?
    /// The page's width breakpoints, read while the responsive mode shows them.
    private(set) var mediaQueries: [MediaQuery] = []

    /// The stored form of the tab, kept in step with the properties above.
    @ObservationIgnored private(set) var node: SidebarNode
    /// Called after the URL or title changed, to save the tab.
    @ObservationIgnored var onChange: ((Tab) -> Void)?
    /// Called when the page opens a link in a new tab or window, with the new page.
    @ObservationIgnored var onOpenPage: ((Tab, FLXBrowserView, FLXOpenDisposition) -> Void)?
    @ObservationIgnored private let profile: FLXProfile
    @ObservationIgnored private let favicons: FaviconCache
    @ObservationIgnored private var loadedView: FLXBrowserView?
    /// Where the page was scrolled before Flux quit or the tab was unloaded, until it has loaded.
    @ObservationIgnored private var scrollToRestore: Double?
    @ObservationIgnored private var pendingDevToolsScript: String?
    @ObservationIgnored private var emulationScale: Double?
    @ObservationIgnored private var appliedEmulation: Emulation?
    @ObservationIgnored private var menuItems: [PageMenuItem] = []

    private enum PageMenuItem {
        case translateSelection, translatePage, showOriginal
    }

    /// `page` is a page already created, opened by another tab.
    init(node: SidebarNode, profile: FLXProfile, favicons: FaviconCache, page: FLXBrowserView? = nil) {
        id = node.id
        spaceID = node.spaceID
        url = node.url ?? ""
        title = node.title
        self.node = node
        self.profile = profile
        self.favicons = favicons
        favicon = favicons.image(for: node.url ?? "")
        super.init()
        if let page {
            page.delegate = self
            loadedView = page
            isLoaded = true
        }
    }

    /// Created on first use, so tabs restored at launch don't load their page until shown.
    var browserView: FLXBrowserView {
        if let loadedView {
            return loadedView
        }
        let view = FLXBrowserView(url: url, profile: profile)
        view.delegate = self
        scrollToRestore = node.scrollY
        loadedView = view
        isLoaded = true
        return view
    }

    var displayTitle: String {
        title.isEmpty ? url : title
    }

    var isPinned: Bool {
        node.section == .pinned
    }

    /// Pinned tabs and favorites stay in the sidebar until removed. Today's tabs go when closed.
    var isKept: Bool {
        node.section != .today
    }

    /// True for a kept tab that has navigated away from the page it was kept on.
    var hasLeftOriginalURL: Bool {
        guard isKept, let originalURL = node.originalURL else { return false }
        return originalURL != url
    }

    func load(_ url: String) {
        browserView.loadURL(url)
        update(url: url)
    }

    /// Shows a tool of the page's DevTools, opening them on it if they are closed. DevTools are
    /// driven through InspectorFrontendAPI, the interface Chrome itself uses to drive them.
    func show(_ tool: DevTool) {
        let script = tool == .picker
            ? "InspectorFrontendAPI.showPanel('elements'); InspectorFrontendAPI.enterInspectElementMode(); true"
            : "InspectorFrontendAPI.showPanel('\(tool.panel)'); true"
        if let devTools {
            devTools.evaluateJavaScript(script) { _ in }
        } else {
            pendingDevToolsScript = tool == .picker ? script : nil
            browserView.showDevTools(onPanel: tool.panel)
        }
    }

    /// The frontend takes a moment to load after DevTools open, so the script is tried until it runs.
    private func runPendingDevToolsScript(on devTools: FLXBrowserView, attempts: Int = 20) {
        guard let script = pendingDevToolsScript, attempts > 0 else { return }
        devTools.evaluateJavaScript("typeof InspectorFrontendAPI === 'undefined' ? false : (\(script))") { [weak self] value in
            if value as? Bool == true {
                self?.pendingDevToolsScript = nil
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.runPendingDevToolsScript(on: devTools, attempts: attempts - 1)
                }
            }
        }
    }

    /// Turns the responsive mode on, at a size of its own, or off.
    func toggleResponsive() {
        update(emulation == nil ? Emulation(device: nil, width: 400, height: 800) : nil)
    }

    func resetEmulation() {
        guard emulation != nil else { return }
        update(Emulation(device: nil, width: 400, height: 800))
    }

    func emulate(_ device: EmulatedDevice?) {
        guard var emulation else { return }
        emulation.device = device
        if let device {
            (emulation.width, emulation.height) = (device.width, device.height)
            emulation.scale = device.scale
            emulation.type = device.isMobile ? .mobile : .desktop
        }
        update(emulation)
    }

    /// A size typed or dragged is Responsive's.
    func resize(width: Int, height: Int) {
        guard var emulation else { return }
        emulation.device = nil
        emulation.width = min(max(width, 50), 4000)
        emulation.height = min(max(height, 50), 4000)
        update(emulation)
    }

    func rotate() {
        guard var emulation else { return }
        (emulation.width, emulation.height) = (emulation.height, emulation.width)
        update(emulation)
    }

    func setPixelRatio(_ scale: Double) {
        guard var emulation else { return }
        emulation.device = nil
        emulation.scale = scale
        update(emulation)
    }

    func setDeviceType(_ type: EmulatedDeviceType) {
        guard var emulation else { return }
        emulation.device = nil
        emulation.type = type
        update(emulation)
    }

    func zoom(_ zoom: EmulationZoom) {
        emulation?.zoom = zoom
    }

    func throttle(_ throttling: NetworkThrottling) {
        guard var emulation else { return }
        emulation.throttling = throttling
        update(emulation)
    }

    /// Sends what changed. The window then sizes the page and applies the size at the scale that
    /// fits, through applyEmulation(scale:).
    private func update(_ new: Emulation?) {
        let old = emulation
        emulation = new
        emulationScale = nil
        let page = browserView
        if new == nil {
            page.sendDevToolsMethod("Emulation.clearDeviceMetricsOverride", params: nil) { _ in }
        }
        if old?.type.hasTouch != new?.type.hasTouch {
            page.sendDevToolsMethod("Emulation.setTouchEmulationEnabled", params: ["enabled": new?.type.hasTouch == true, "maxTouchPoints": 5]) { _ in }
        }
        if old?.throttling != new?.throttling {
            page.sendDevToolsMethod("Network.enable", params: nil) { _ in }
            page.sendDevToolsMethod("Network.emulateNetworkConditions", params: (new?.throttling ?? .none).conditions) { _ in }
        }
        // Sites choose their mobile pages from this, read when the page loads.
        if old?.userAgent != new?.userAgent {
            page.sendDevToolsMethod("Emulation.setUserAgentOverride", params: ["userAgent": new?.userAgent ?? ""]) { _ in
                page.reload()
            }
        }
    }

    /// The protocol only lists media queries while its CSS domain is on, which makes Chromium report
    /// every stylesheet change, so it is turned off again once they are read.
    func loadMediaQueries() {
        let page = browserView
        page.sendDevToolsMethod("DOM.enable", params: nil) { _ in
            page.sendDevToolsMethod("CSS.enable", params: nil) { _ in
                page.sendDevToolsMethod("CSS.getMediaQueries", params: nil) { [weak self] result in
                    self?.mediaQueries = MediaQuery.parse(result)
                    page.sendDevToolsMethod("CSS.disable", params: nil) { _ in }
                    page.sendDevToolsMethod("DOM.disable", params: nil) { _ in }
                }
            }
        }
    }

    /// `scale` shrinks or enlarges the page in the room it has.
    func applyEmulation(scale: Double) {
        guard let emulation, scale != emulationScale || emulation != appliedEmulation else { return }
        emulationScale = scale
        appliedEmulation = emulation
        browserView.sendDevToolsMethod("Emulation.setDeviceMetricsOverride", params: [
            "width": emulation.width, "height": emulation.height, "deviceScaleFactor": emulation.scale,
            "mobile": emulation.type.isMobile, "scale": scale,
            "screenWidth": emulation.width, "screenHeight": emulation.height,
            "screenOrientation": [
                "type": emulation.isLandscape ? "landscapePrimary" : "portraitPrimary", "angle": emulation.isLandscape ? 90 : 0,
            ],
        ]) { _ in }
    }

    /// The page's result, when it is a string. A page left while the script runs never answers,
    /// so the wait ends after a few seconds.
    func evaluate(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            var isDone = false
            let finish = { (value: String?) in
                guard !isDone else { return }
                isDone = true
                continuation.resume(returning: value)
            }
            browserView.evaluateJavaScript(script) { value in finish(value as? String) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
    }

    var canTranslatePage: Bool {
        PageTranslator.shared.isAvailable && translation == nil && !(pageLanguage.map { PageTranslator.sameLanguage($0, PageTranslator.targetLanguage(for: profile)) } ?? false)
    }

    func translatePage() {
        let target = PageTranslator.targetLanguage(for: profile)
        Task {
            if pageLanguage == nil { await detectPageLanguage() }
            guard let source = pageLanguage, !PageTranslator.sameLanguage(source, target) else { return }
            translation = PageTranslation(source: source, target: target)
            PageTranslator.shared.start(self)
        }
    }

    func showOriginal() {
        translation = nil
        PageTranslator.shared.stop(self)
        browserView.evaluateJavaScript(PageTranslationScript.restore) { _ in }
    }

    func setTranslating(_ isTranslating: Bool) {
        self.isTranslating = isTranslating
    }

    func translationFailed(_ error: Error) {
        translation = nil
        isTranslating = false
        guard let window = NSApp.windows.first(where: { $0 is MainWindow }) else { return }
        Toast.show(error.localizedDescription, over: window)
    }

    private struct LanguageSample: Decodable {
        let lang: String
        let text: String
    }

    private func detectPageLanguage() async {
        guard let json = await evaluate(PageTranslationScript.sample),
              let sample = try? JSONDecoder().decode(LanguageSample.self, from: Data(json.utf8)) else { return }
        pageLanguage = PageTranslator.language(ofText: sample.text, declared: sample.lang)
        // Pages in the same language go on being translated, others are left as they are.
        guard let translation else { return }
        if let pageLanguage, !PageTranslator.sameLanguage(pageLanguage, translation.source) {
            self.translation = nil
            PageTranslator.shared.stop(self)
        } else {
            PageTranslator.shared.start(self)
        }
    }

    /// Only this site's cookies, then the page loads again without them.
    func clearCookiesAndReload() {
        guard let url = URL(string: url), let scheme = url.scheme, let host = url.host() else { return }
        let origin = url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
        let page = browserView
        page.sendDevToolsMethod("Storage.clearDataForOrigin", params: ["origin": origin, "storageTypes": "cookies"]) { _ in
            page.reload()
        }
    }

    func goBackToOriginalURL() {
        guard let originalURL = node.originalURL else { return }
        load(originalURL)
    }

    func setShare(_ share: Double?) {
        node.share = share
    }

    func markActive() {
        node.lastActiveAt = Date()
        onChange?(self)
    }

    func place(section: SidebarNode.Section, parentID: UUID?, position: String) {
        if section == .today {
            node.originalURL = nil
            // Counts as seen now, or a tab kept long ago would be archived right away.
            if node.section != .today { node.lastActiveAt = Date() }
        } else if node.section == .today {
            node.originalURL = url
        }
        node.section = section
        node.parentID = parentID
        node.position = position
    }

    /// Frees the page's memory. The tab stays and loads again when shown, where it was scrolled.
    func unload() {
        guard let view = loadedView else { return }
        loadedView = nil
        isLoaded = false
        saveScrollPosition(of: view) { view.close() }
    }

    func saveScrollPosition(completion: @escaping () -> Void = {}) {
        guard let loadedView else { return completion() }
        saveScrollPosition(of: loadedView, completion: completion)
    }

    private func saveScrollPosition(of view: FLXBrowserView, completion: @escaping () -> Void) {
        let url = url
        view.evaluateJavaScript("window.scrollY") { [weak self] value in
            if let self, self.url == url, let y = value as? Double {
                self.node.scrollY = y > 0 ? y : nil
                self.onChange?(self)
            }
            completion()
        }
    }

    func close() {
        loadedView?.close()
    }

    private func update(url: String? = nil, title: String? = nil) {
        if let url {
            if url != node.url { node.scrollY = nil }
            self.url = url
            node.url = url
            favicon = favicons.image(for: url) ?? favicon
        }
        if let title {
            self.title = title
            node.title = title
        }
        onChange?(self)
    }
}

extension Tab: FLXBrowserViewDelegate {
    func browserView(_ browserView: FLXBrowserView, didChangeURL url: String) {
        update(url: url)
    }

    func browserView(_ browserView: FLXBrowserView, didChangeTitle title: String) {
        update(title: title)
    }

    func browserView(_ browserView: FLXBrowserView, didOpenPage page: FLXBrowserView, disposition: FLXOpenDisposition) {
        onOpenPage?(self, page, disposition)
    }

    func browserView(_ browserView: FLXBrowserView, didOpenDevTools devTools: FLXBrowserView) {
        self.devTools = devTools
        runPendingDevToolsScript(on: devTools)
    }

    func browserViewDidCloseDevTools(_ browserView: FLXBrowserView) {
        devTools = nil
    }

    func browserViewDidChangeNavigationState(_ browserView: FLXBrowserView) {
        canGoBack = browserView.canGoBack
        canGoForward = browserView.canGoForward
    }

    func browserView(_ browserView: FLXBrowserView, contextMenuItemsForSelectedText selectedText: String) -> [String] {
        menuItems = selectedText.isEmpty ? [] : [.translateSelection]
        if translation != nil {
            menuItems.append(.showOriginal)
        } else if canTranslatePage {
            menuItems.append(.translatePage)
        }
        let language = Locale.current.localizedString(forLanguageCode: PageTranslator.targetLanguage(for: profile).languageCode?.identifier ?? "") ?? ""
        return menuItems.map { item in
            switch item {
            case .translateSelection: String(localized: "Translate Selection")
            case .translatePage: String(localized: "Translate Page into \(language)")
            case .showOriginal: String(localized: "Show Original")
            }
        }
    }

    func browserView(_ browserView: FLXBrowserView, didChooseContextMenuItemAt index: Int, selectedText: String, point: NSPoint) {
        guard menuItems.indices.contains(index) else { return }
        switch menuItems[index] {
        case .translateSelection: SelectionTranslation.show(selectedText, at: point)
        case .translatePage: translatePage()
        case .showOriginal: showOriginal()
        }
    }

    func browserViewDidFinishLoading(_ browserView: FLXBrowserView) {
        Task { await detectPageLanguage() }
        if emulation != nil { loadMediaQueries() }
        guard let y = scrollToRestore else { return }
        scrollToRestore = nil
        browserView.evaluateJavaScript("window.scrollTo(0, \(y))") { _ in }
    }

    func browserView(_ browserView: FLXBrowserView, didChangeFavicon favicon: NSImage) {
        self.favicon = favicon
        favicons.store(favicon, for: url)
    }
}
