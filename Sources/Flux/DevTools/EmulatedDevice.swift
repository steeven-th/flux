import Foundation

/// A device the responsive mode can show a page as: its screen, its pixel density, and what it
/// says it is to websites.
struct EmulatedDevice: Identifiable, Hashable, Codable {
    enum Category: String, CaseIterable, Codable {
        case mobile, foldable, tablet, display, custom

        var name: String {
            switch self {
            case .mobile: String(localized: "Mobile")
            case .foldable: String(localized: "Foldables")
            case .tablet: String(localized: "Tablets and Computers")
            case .display: String(localized: "Smart Displays")
            case .custom: String(localized: "Custom")
            }
        }
    }

    var id: String
    var name: String
    var category: Category
    var width: Int
    var height: Int
    var scale: Double
    var isMobile: Bool
    /// Nil for the browser's own, or a generic mobile one when the device is mobile.
    var userAgent: String?

    static func custom() -> EmulatedDevice {
        EmulatedDevice(id: UUID().uuidString, name: "", category: .custom, width: 400, height: 800, scale: 2, isMobile: true, userAgent: nil)
    }

    private static let iOS = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private static let iPadOS = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let genericMobileUserAgent = android
    private static let android = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
    private static let androidTablet = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private static let windows = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private static let nest = "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) CrKey/1.54.250320 Chrome/130.0.0.0 Safari/537.36"

    private static func device(
        _ id: String, _ name: String, _ category: Category, _ width: Int, _ height: Int, _ scale: Double,
        mobile: Bool = true, _ userAgent: String?
    ) -> EmulatedDevice {
        EmulatedDevice(id: id, name: name, category: category, width: width, height: height, scale: scale, isMobile: mobile, userAgent: userAgent)
    }

    static let all: [EmulatedDevice] = [
        device("iphone-se", "iPhone SE", .mobile, 375, 667, 2, iOS),
        device("iphone-16", "iPhone 16", .mobile, 393, 852, 3, iOS),
        device("iphone-16-pro-max", "iPhone 16 Pro Max", .mobile, 440, 956, 3, iOS),
        device("pixel-9", "Pixel 9", .mobile, 412, 915, 2.625, android),
        device("pixel-9-pro", "Pixel 9 Pro", .mobile, 427, 952, 3, android),
        device("galaxy-s24", "Samsung Galaxy S24", .mobile, 384, 832, 3, android),
        device("pixel-9-pro-fold", "Pixel 9 Pro Fold", .foldable, 615, 768, 2.625, android),
        device("galaxy-z-fold-6", "Galaxy Z Fold 6", .foldable, 549, 883, 2.625, android),
        device("ipad-mini", "iPad mini", .tablet, 744, 1133, 2, iPadOS),
        device("ipad-air", "iPad Air", .tablet, 820, 1180, 2, iPadOS),
        device("ipad-pro", "iPad Pro 13\"", .tablet, 1032, 1376, 2, iPadOS),
        device("surface-pro", "Surface Pro", .tablet, 1440, 960, 2, mobile: false, windows),
        device("galaxy-tab-s9", "Galaxy Tab S9", .tablet, 800, 1280, 2, androidTablet),
        device("nest-hub-max", "Nest Hub Max", .display, 1280, 800, 2, mobile: false, nest),
    ]
}

enum EmulationZoom: Hashable, CaseIterable {
    case fit, half, threeQuarters, actual, larger, largest

    /// Nil to fit the page in the room it has.
    var value: Double? {
        switch self {
        case .fit: nil
        case .half: 0.5
        case .threeQuarters: 0.75
        case .actual: 1
        case .larger: 1.25
        case .largest: 1.5
        }
    }

    var name: String {
        guard let value else { return String(localized: "Fit to Window") }
        return value.formatted(.percent)
    }
}

/// Network conditions the page can be loaded under, like DevTools' throttling presets.
enum NetworkThrottling: Hashable, CaseIterable {
    case none, fast4G, slow4G, offline

    var name: String {
        switch self {
        case .none: String(localized: "No Throttling")
        case .fast4G: String(localized: "Fast 4G")
        case .slow4G: String(localized: "Slow 4G")
        case .offline: String(localized: "Offline")
        }
    }

    /// For the protocol's Network.emulateNetworkConditions. Throughputs are in bytes per second.
    var conditions: [String: Any] {
        switch self {
        case .none: ["offline": false, "latency": 0, "downloadThroughput": -1, "uploadThroughput": -1]
        case .fast4G: ["offline": false, "latency": 60, "downloadThroughput": 9_000_000 / 8, "uploadThroughput": 1_500_000 / 8]
        case .slow4G: ["offline": false, "latency": 150, "downloadThroughput": 1_600_000 / 8, "uploadThroughput": 750_000 / 8]
        case .offline: ["offline": true, "latency": 0, "downloadThroughput": 0, "uploadThroughput": 0]
        }
    }
}

/// How the page is told it is used, like DevTools' device type.
enum EmulatedDeviceType: Hashable, CaseIterable {
    case mobile, desktop, mobileWithoutTouch, desktopWithTouch

    var name: String {
        switch self {
        case .mobile: String(localized: "Mobile")
        case .desktop: String(localized: "Desktop")
        case .mobileWithoutTouch: String(localized: "Mobile (No Touch)")
        case .desktopWithTouch: String(localized: "Desktop (Touch)")
        }
    }

    var isMobile: Bool { self == .mobile || self == .mobileWithoutTouch }
    var hasTouch: Bool { self == .mobile || self == .desktopWithTouch }
}

/// What the responsive mode shows a page as.
struct Emulation: Equatable {
    /// Nil in Responsive, where the size is free.
    var device: EmulatedDevice?
    var width: Int
    var height: Int
    var scale: Double = 2
    var type = EmulatedDeviceType.desktop
    var zoom = EmulationZoom.fit
    var throttling = NetworkThrottling.none

    /// A device's own user agent, or a generic one for Responsive set to mobile.
    var userAgent: String? {
        if let device { return device.userAgent ?? (device.isMobile ? EmulatedDevice.genericMobileUserAgent : nil) }
        return type.isMobile ? EmulatedDevice.genericMobileUserAgent : nil
    }

    var isLandscape: Bool { width > height }
}

/// The background around a page in responsive mode.
enum ResponsiveBackdrop: String, CaseIterable {
    case system, dark, light

    var name: String {
        switch self {
        case .system: String(localized: "System")
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        }
    }
}

enum ResponsiveOption: String, Codable {
    case rulers, pixelRatio, deviceType
}
