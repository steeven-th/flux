import SwiftUI

/// Controls for what a tab plays while the tab isn't shown, at the bottom of the sidebar, as in
/// Arc. Hovering shows the title, a button that stops and closes it, and the page's volume.
struct MiniPlayer: View {
    let state: BrowserState
    let tab: Tab
    /// Set in a spread stack, which decides when each card shows its title and volume. Alone, the
    /// card shows them while hovered.
    var showsDetails: Bool?
    var onHover: (Bool) -> Void = { _ in }

    @State private var isHovered = false

    private static let controlsHeight: CGFloat = 24
    private static let verticalPadding: CGFloat = 6
    static let compactHeight = controlsHeight + 2 * verticalPadding
    /// The title and the slider fade in once the card has almost grown to make room for them.
    private static let reveal = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.12).delay(0.12)),
        removal: .opacity.animation(.easeOut(duration: 0.06))
    )

    var body: some View {
        let media = tab.media
        return VStack(spacing: 8) {
            if showsDetails ?? isHovered {
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
                .transition(Self.reveal)
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
                    .frame(maxWidth: .infinity, minHeight: Self.controlsHeight, maxHeight: Self.controlsHeight)
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

            if showsDetails ?? isHovered {
                Slider(value: volume, in: 0...1)
                    .controlSize(.mini)
                    .transition(Self.reveal)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, Self.verticalPadding)
        .miniPlayerCard()
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .animation(.easeOut(duration: 0.18), value: showsDetails ?? isHovered)
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
                .frame(maxWidth: .infinity, minHeight: Self.controlsHeight, maxHeight: Self.controlsHeight)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}

/// The mini players of several tabs, stacked as in Arc: the latest in front, two of the others
/// showing behind it. Hovering the stack spreads it out upwards.
struct MiniPlayerStack: View {
    let state: BrowserState

    @State private var isSpread = false
    /// How many cards of the spread stack show their details, from the bottom: up to the highest
    /// one hovered, until the pointer goes down to a lower one or leaves the stack.
    @State private var detailedCount = 0
    @State private var collapse: Task<Void, Never>?

    private static let maximumSpread = 4
    private static let maximumBehind = 2

    /// Grown or spread, the stack takes room from the tab list rather than going over it: the list
    /// is an AppKit view, which takes the pointer wherever it is under the stack.
    var body: some View {
        let tabs = state.miniPlayerTabs
        // One container whatever the content, so that the pointer stays over the same view when the
        // stack spreads.
        return VStack(spacing: 0) {
            if isSpread && tabs.count > 1 {
                VStack(spacing: 6) {
                    ForEach(Array(tabs.prefix(Self.maximumSpread).enumerated()).reversed(), id: \.element.id) { index, tab in
                        MiniPlayer(state: state, tab: tab, showsDetails: index < detailedCount) { hovering in
                            if hovering { detailedCount = index + 1 }
                        }
                    }
                }
            } else if let front = tabs.first {
                MiniPlayer(state: state, tab: front)
                    .id(front.id)
                    .background(alignment: .bottom) {
                        ZStack(alignment: .bottom) {
                            ForEach(Array(1..<min(tabs.count, Self.maximumBehind + 1)).reversed(), id: \.self) { depth in
                                Color.clear
                                    .frame(height: MiniPlayer.compactHeight)
                                    .miniPlayerCard()
                                    .scaleEffect(x: 1 - 0.06 * CGFloat(depth), anchor: .bottom)
                                    .offset(y: -5 * CGFloat(depth))
                            }
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            collapse?.cancel()
            if hovering {
                if !isSpread {
                    isSpread = true
                    // The pointer is on the front card, which becomes the bottom one. It only shows
                    // its details once spread, so that it grows as when it is alone.
                    DispatchQueue.main.async {
                        if isSpread && detailedCount == 0 { detailedCount = 1 }
                    }
                }
            } else {
                // Leaving it for a moment, on the way between two cards, keeps it spread.
                collapse = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled {
                        isSpread = false
                        detailedCount = 0
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isSpread)
        .animation(.easeOut(duration: 0.18), value: detailedCount)
        .animation(.easeOut(duration: 0.2), value: tabs.map(\.id))
    }
}

private extension View {
    func miniPlayerCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        // Opaque enough to hide the cards stacked behind it.
        return background(shape.fill(.background.opacity(0.95)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.08)))
    }
}
