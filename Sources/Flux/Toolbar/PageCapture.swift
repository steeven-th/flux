import AppKit

/// Screenshots of a page, taken by Chromium rather than from the screen, so a whole page can be
/// captured beyond what the window shows. Each one is copied and saved to the Downloads folder.
@MainActor
enum PageCapture {
    /// Chromium refuses images taller than this.
    private static let maximumHeight = 16_384.0

    static func captureWholePage(_ page: FLXBrowserView, completion: @escaping (URL?) -> Void) {
        page.sendDevToolsMethod("Page.getLayoutMetrics", params: nil) { metrics in
            let size = metrics?["cssContentSize"] as? [String: Double] ?? [:]
            let width = size["width"] ?? 0
            let height = min(size["height"] ?? 0, maximumHeight)
            let scale = height * 2 <= maximumHeight ? 2.0 : 1.0
            capture(page, clip: CGRect(x: 0, y: 0, width: width, height: height), scale: scale, completion: completion)
        }
    }

    /// `area` is in the page view's points, from its top left corner.
    static func capture(_ page: FLXBrowserView, area: CGRect, completion: @escaping (URL?) -> Void) {
        page.sendDevToolsMethod("Page.getLayoutMetrics", params: nil) { metrics in
            // The clip is in document coordinates, so the scroll position is added.
            let viewport = metrics?["cssVisualViewport"] as? [String: Double] ?? [:]
            let clip = area.offsetBy(dx: viewport["pageX"] ?? 0, dy: viewport["pageY"] ?? 0)
            capture(page, clip: clip, scale: Double(page.window?.backingScaleFactor ?? 2), completion: completion)
        }
    }

    private static func capture(_ page: FLXBrowserView, clip: CGRect, scale: Double, completion: @escaping (URL?) -> Void) {
        let params: [String: Any] = [
            "format": "png",
            "captureBeyondViewport": true,
            "clip": ["x": clip.minX, "y": clip.minY, "width": clip.width, "height": clip.height, "scale": scale],
        ]
        page.sendDevToolsMethod("Page.captureScreenshot", params: params) { result in
            guard let base64 = result?["data"] as? String, let data = Data(base64Encoded: base64) else {
                return completion(nil)
            }
            completion(save(data))
        }
    }

    /// Lets the user pick an area of the tab's page, then captures it.
    static func captureArea(of tab: Tab, state: BrowserState) {
        let page = tab.browserView
        AreaSelector.select(over: page) { area in
            guard let area else { return }
            capture(page, area: area) { finished($0, state: state) }
        }
    }

    /// What the page shows, at the size and density of the device it is shown as.
    static func captureVisibleArea(of tab: Tab, state: BrowserState) {
        let page = tab.browserView
        page.sendDevToolsMethod("Page.getLayoutMetrics", params: nil) { metrics in
            let viewport = metrics?["cssVisualViewport"] as? [String: Double] ?? [:]
            let clip = CGRect(x: viewport["pageX"] ?? 0, y: viewport["pageY"] ?? 0, width: viewport["clientWidth"] ?? 0, height: viewport["clientHeight"] ?? 0)
            capture(page, clip: clip, scale: 1) { finished($0, state: state) }
        }
    }

    static func captureWholePage(of tab: Tab, state: BrowserState) {
        captureWholePage(tab.browserView) { finished($0, state: state) }
    }

    private static func finished(_ url: URL?, state: BrowserState) {
        guard let window = MainWindow.active else { return }
        Toast.show(url == nil ? String(localized: "The capture failed") : String(localized: "Capture copied and saved to Downloads"), over: window)
        state.mediaLibrary.refresh()
    }

    private static func save(_ data: Data) -> URL? {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let date = Date().formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current
        ))
        let url = folder.appending(path: String(localized: "Flux Capture \(date)") + ".png")
        guard (try? data.write(to: url)) != nil else { return nil }
        NSPasteboard.general.clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        if let image = NSImage(data: data) { objects.insert(image, at: 0) }
        NSPasteboard.general.writeObjects(objects)
        return url
    }
}

/// A short message over the top of a window, fading away on its own.
@MainActor
enum Toast {
    static func show(_ message: String, over host: NSWindow) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 32, height: 34)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2
        background.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: 16, y: (size.height - label.frame.height) / 2)
        background.addSubview(label)
        window.contentView = background

        let frame = host.frame
        window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 48))
        host.addChildWindow(window, ordered: .above)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    host.removeChildWindow(window)
                    window.orderOut(nil)
                }
            }
        }
    }
}
