import Foundation

/// A tool of Chromium's DevTools that the developer bar can open in one click.
enum DevTool: String, CaseIterable, Identifiable, Codable {
    case picker, elements, console, network, application, sources, performance, memory, security, lighthouse, recorder

    var id: Self { self }

    /// The panel's name in the DevTools frontend. The picker opens on Elements.
    var panel: String {
        switch self {
        case .picker, .elements: "elements"
        case .console: "console"
        case .network: "network"
        case .application: "resources"
        case .sources: "sources"
        case .performance: "timeline"
        case .memory: "heap-profiler"
        case .security: "security"
        case .lighthouse: "lighthouse"
        case .recorder: "chrome-recorder"
        }
    }

    var symbol: String {
        switch self {
        case .picker: "scope"
        case .elements: "chevron.left.forwardslash.chevron.right"
        case .console: "terminal"
        case .network: "network"
        case .application: "internaldrive"
        case .sources: "doc.text"
        case .performance: "gauge.with.dots.needle.67percent"
        case .memory: "memorychip"
        case .security: "lock.shield"
        case .lighthouse: "light.beacon.max"
        case .recorder: "record.circle"
        }
    }

    var name: String {
        switch self {
        case .picker: String(localized: "Select an Element")
        case .elements: String(localized: "Elements")
        case .console: String(localized: "Console")
        case .network: String(localized: "Network")
        case .application: String(localized: "Application")
        case .sources: String(localized: "Sources")
        case .performance: String(localized: "Performance")
        case .memory: String(localized: "Memory")
        case .security: String(localized: "Security")
        case .lighthouse: "Lighthouse"
        case .recorder: String(localized: "Recorder")
        }
    }

    /// Like Arc's developer mode.
    static let standard: [DevTool] = [.picker, .console, .network]
}
