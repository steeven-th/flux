import SwiftUI

/// Controls for what a tab plays while the tab isn't shown, at the bottom of the sidebar, as in
/// Arc. Hovering shows the title, a button that stops and closes it, and the page's volume.
struct MiniPlayer: View {
    let state: BrowserState
    let tab: Tab

    @State private var isHovered = false

    var body: some View {
        let media = tab.media
        VStack(spacing: 8) {
            if isHovered {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Button {
                        tab.send(.pause)
                        tab.isMediaDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .help("Stop and Close")
                }
                .transition(.opacity)
            }

            HStack(spacing: 0) {
                Button { state.show(tab) } label: {
                    Group {
                        if let favicon = tab.favicon {
                            Image(nsImage: favicon).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "globe").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .contentShape(Rectangle())
                }
                .help("Show Tab")
                control("backward.end.fill", help: "Previous") { tab.send(.previous) }
                    .disabled(media?.hasPrevious != true)
                control(media?.isPlaying == true ? "pause.fill" : "play.fill", help: media?.isPlaying == true ? "Pause" : "Play") {
                    tab.send(media?.isPlaying == true ? .pause : .play)
                }
                control("forward.end.fill", help: "Next") { tab.send(.next) }
                    .disabled(media?.hasNext != true)
                control(tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: tab.isMuted ? "Unmute Tab" : "Mute Tab") {
                    tab.toggleMute()
                }
            }

            if isHovered {
                Slider(value: volume, in: 0...1)
                    .controlSize(.mini)
                    .transition(.opacity)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    /// The site's title for what plays, else the page's.
    private var title: String {
        guard let media = tab.media, !media.title.isEmpty else { return tab.displayTitle }
        return media.artist.isEmpty ? media.title : "\(media.title) · \(media.artist)"
    }

    private var volume: Binding<Double> {
        Binding(get: { tab.media?.volume ?? 1 }, set: { tab.send(.volume($0)) })
    }

    private func control(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}
