import SwiftUI

struct WelcomeView: View {
    @Bindable var model: WelcomeModel
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch model.step {
                case .welcome: IntroStep()
                case .imports: ImportStep(model: model)
                case .space: SpaceStep(model: model)
                case .searchEngine: SearchEngineStep(model: model)
                case .passwords: PasswordsStep(model: model)
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if model.step != .welcome {
                    Button("Back", action: model.goBack)
                }
                Spacer()
                Button(primaryTitle, action: next)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .frame(width: 560, height: 520)
        // From the first space on, the window takes the space's color, as Flux's window will.
        .background {
            Color(hex: model.color)
                .opacity(model.step.rawValue >= WelcomeModel.Step.space.rawValue ? SpaceBackground.tintOpacity : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: model.color)
                .animation(.easeInOut(duration: 0.3), value: model.step)
        }
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case .welcome: "Get Started"
        case .done: "Start Browsing"
        default: "Continue"
        }
    }

    private func next() {
        if model.step == .done {
            finish()
        } else {
            model.goForward()
        }
    }
}

private struct StepHeader: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 24)
    }
}

private struct ImportStep: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.sources.count == 1, let only = model.sources.first {
                StepHeader(title: "Coming from \(only.source.name)?", message: "Flux can bring your spaces, with their pinned tabs, favorites, folders, history, passwords and sign-ins. \(only.source.name) itself is left as it is.")
            } else {
                StepHeader(title: "Coming from another browser?", message: "Flux can bring your spaces, with their pinned tabs, favorites, folders, history, passwords and sign-ins. The other browser is left as it is.")
            }
            Picker(selection: $model.importSource) {
                ForEach(model.sources, id: \.source) { source, spaces in
                    let tabs = spaces.reduce(0) { $0 + $1.tabCount }
                    Text("Import my \(spaces.count) \(source.name) spaces (\(tabs) tabs)").tag(ImportSource?.some(source))
                }
                Text("Start with a new space").tag(ImportSource?.none)
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if !model.waitingSources.isEmpty {
                AppDataAccessHint(sources: model.waitingSources)
            }
            if model.importSource?.hasToday == true {
                Toggle("Also import Today's tabs", isOn: $model.importsToday)
                    .padding(.leading, 20)
            }
            Text("You can import them later from File > Import from Another Browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct IntroStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            StepHeader(
                title: "Welcome to Flux",
                message: "Your tabs live in a sidebar. Spaces keep your sign-ins, passwords and extensions apart, and the Chrome extensions you use work here too."
            )
        }
    }
}

private struct SpaceStep: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading) {
            StepHeader(
                title: "Your first space",
                message: "Each space has its own sign-ins, passwords, history and extensions. Add more later with + at the bottom of the sidebar."
            )
            HStack(alignment: .top, spacing: 32) {
                SpaceFields(name: $model.name, icon: $model.icon, color: $model.color)
                    .frame(width: 260)
                SidebarPreview(model: model)
            }
        }
    }
}

/// A sketch of the sidebar, to show what the chosen color and icon look like.
private struct SidebarPreview: View {
    let model: WelcomeModel

    private let rowWidths: [CGFloat] = [96, 120, 72, 104]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.07)).frame(height: 22)
            ForEach(rowWidths, id: \.self) { width in
                RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.1)).frame(width: width, height: 8)
            }
            Spacer()
            HStack(spacing: 6) {
                SpaceIcon(name: model.name, icon: model.icon, color: Color(hex: model.color), isSelected: true)
                Text(model.name).font(.caption).lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 170, height: 200, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: model.color).opacity(0.2))
                .animation(.easeInOut(duration: 0.3), value: model.color)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1))
        }
    }
}

private struct SearchEngineStep: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading) {
            StepHeader(
                title: "Search engine",
                message: "Used when what you type in the command bar isn't an address. You can change it in Settings."
            )
            Picker("Search engine", selection: $model.searchEngine) {
                ForEach(SearchEngine.all) { engine in
                    Text(engine.name).tag(engine)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }
}

private struct PasswordsStep: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading) {
            StepHeader(
                title: "Passwords",
                message: "Which password manager do you use? If it isn't Chromium's, its page on the Chrome Web Store opens at the end so you can add it."
            )
            Picker("Password manager", selection: $model.passwordManager) {
                Text("Chromium Password Manager, on this Mac, no account needed")
                    .tag(PasswordManagerExtension?.none)
                ForEach(PasswordManagerExtension.all) { manager in
                    Text(verbatim: manager.name).tag(Optional(manager))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }
}

private struct DoneStep: View {
    @State private var isDefaultBrowser = DefaultBrowser.isFlux

    private let shortcuts: [(keys: String, action: LocalizedStringKey)] = [
        ("⌘T", "Search or open a page"),
        ("⌘S", "Show or hide the sidebar"),
        ("⌃1 – ⌃9", "Switch spaces"),
        ("⌘D", "Pin a tab"),
        ("⌘,", "Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading) {
            StepHeader(title: "You're all set", message: "A few shortcuts to start with:")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(shortcuts, id: \.keys) { shortcut in
                    GridRow {
                        Text(verbatim: shortcut.keys)
                            .font(.body.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                        Text(shortcut.action)
                    }
                }
            }
            .padding(.bottom, 24)
            if isDefaultBrowser {
                Label("Flux is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button("Make Flux the Default Browser") {
                    DefaultBrowser.makeFlux { isDefaultBrowser = $0 }
                }
            }
        }
    }
}
