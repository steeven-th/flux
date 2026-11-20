import AppKit
import EventKit
import SwiftUI

/// Web calendars whose tile shows the next meeting.
enum CalendarSite {
    static func matches(_ address: String) -> Bool {
        guard let url = URL(string: address), let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return host == "calendar.google.com"
            || host == "calendar.proton.me"
            || host == "app.fastmail.com" && path.hasPrefix("/calendar")
            || host.hasPrefix("outlook.") && path.contains("/calendar")
            || host.hasSuffix("icloud.com") && path.hasPrefix("/calendar")
            || host == "calendar.notion.so"
    }
}

/// The next meeting in the Mac's calendars, which hold Google's, iCloud's and Exchange's when the
/// user added the accounts. Read with EventKit rather than from the page, which changes with each
/// site and each redesign.
@MainActor
@Observable
final class CalendarAgenda {
    static let shared = CalendarAgenda()

    struct Meeting: Equatable {
        let title: String
        let start: Date
        let end: Date
        let joinURL: URL?
        let color: NSColor?
    }

    enum Access {
        case unknown, granted, refused
    }

    private(set) var access = CalendarAgenda.currentAccess
    private(set) var next: Meeting?
    @ObservationIgnored private let store = EKEventStore()

    private static var currentAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .refused
        }
    }

    /// Only when asked: the preview offers it rather than asking on a hover.
    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = Self.currentAccess
            refresh()
        }
    }

    func refresh() {
        access = Self.currentAccess
        guard access == .granted else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .min { $0.startDate < $1.startDate }
        next = event.map {
            Meeting(
                title: $0.title ?? "", start: $0.startDate, end: $0.endDate,
                joinURL: Self.joinURL(in: $0), color: $0.calendar.map { NSColor(cgColor: $0.cgColor) } ?? nil
            )
        }
    }

    /// Meet, Zoom, Teams or Webex, wherever the invitation put it.
    private static func joinURL(in event: EKEvent) -> URL? {
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        let pattern = #"https://(meet\.google\.com/[a-z\-]+|[\w.-]*zoom\.us/(j|my|w)/[^\s<>"]+|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|teams\.live\.com/meet/[^\s<>"]+|[\w.-]*webex\.com/[^\s<>"]+)"#
        for text in texts {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return URL(string: String(text[range]))
            }
        }
        return nil
    }
}

/// Above a calendar's preview: the next meeting, and a button to join it.
struct NextMeetingView: View {
    static let height: CGFloat = 56

    let agenda: CalendarAgenda
    let onJoin: (URL) -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch agenda.access {
            case .unknown:
                Image(systemName: "calendar").foregroundStyle(.secondary)
                Text("See your next meeting here, from your Mac's calendars.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Allow…") { agenda.requestAccess() }
            case .refused:
                Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
                Text("Flux can't read your calendars.")
                    .font(.callout)
                Spacer(minLength: 0)
                Button("Open Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            case .granted:
                if let meeting = agenda.next {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: meeting.color ?? .controlAccentColor))
                        .frame(width: 4, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title).font(.callout.weight(.semibold)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(when(meeting, now: context.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let url = meeting.joinURL {
                        Button("Join") { onJoin(url) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text("No more meetings in the next 24 hours.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
    }

    private func when(_ meeting: Meeting, now: Date) -> String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened) + " – " + meeting.end.formatted(date: .omitted, time: .shortened)
        if meeting.start <= now { return String(localized: "Now, \(time)") }
        let minutes = Int(meeting.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return String(localized: "In \(minutes) min, \(time)") }
        return time
    }

    private typealias Meeting = CalendarAgenda.Meeting
}
