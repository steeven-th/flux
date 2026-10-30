import SwiftUI
import UniformTypeIdentifiers

/// One rule in the Links settings: what it matches, and where the link opens.
struct LinkRuleRow: View {
    let state: BrowserState
    let rule: LinkRule
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                condition
                destination
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .help("Edit Rule")
            Button(action: delete) {
                Image(systemName: "trash")
            }
            .help("Delete Rule")
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }

    @ViewBuilder private var condition: some View {
        let text = rule.urlContains ?? ""
        if let app = rule.sourceApp, !text.isEmpty {
            Text("Links containing “\(text)” from \(app.name)")
        } else if let app = rule.sourceApp {
            Text("Links from \(app.name)")
        } else {
            Text("Links containing “\(text)”")
        }
    }

    @ViewBuilder private var destination: some View {
        let space = rule.spaceID.flatMap { id in state.spaces.first { $0.id == id } }
        if let space {
            if rule.opensLittleWindow {
                Text("Open in a little window of \(space.label)")
            } else {
                Text("Open in a new tab of \(space.label)")
            }
        } else if rule.opensLittleWindow {
            Text("Open in a little window of the current space")
        } else {
            Text("Open in a new tab of the current space")
        }
    }
}

struct LinkRuleEditor: View {
    let state: BrowserState
    @State var rule: LinkRule
    let onSave: (LinkRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [SourceApp] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Link contains", text: urlContains, prompt: Text(verbatim: "meet.google.com"))
                    HStack {
                        Picker("From app", selection: $rule.sourceApp) {
                            Text("Any app").tag(SourceApp?.none)
                            if !apps.isEmpty { Divider() }
                            ForEach(apps, id: \.self) { app in
                                Text(verbatim: app.name).tag(Optional(app))
                            }
                        }
                        Button("Choose…", action: chooseApp)
                    }
                } footer: {
                    Text("Apps that sent links to Flux are in the list. When both are set, a link must match both.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("Open in", selection: $rule.spaceID) {
                        Text("The current space").tag(UUID?.none)
                        Divider()
                        ForEach(state.spaces) { space in
                            Text(verbatim: space.label).tag(Optional(space.id))
                        }
                    }
                    Picker("As", selection: $rule.opensLittleWindow) {
                        Text("A new tab").tag(false)
                        Text("A little window").tag(true)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!rule.hasCondition)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            apps = state.linkSourceApps
            if let app = rule.sourceApp, !apps.contains(app) { apps.insert(app, at: 0) }
        }
    }

    private var urlContains: Binding<String> {
        Binding {
            rule.urlContains ?? ""
        } set: { text in
            let text = text.trimmingCharacters(in: .whitespaces)
            rule.urlContains = text.isEmpty ? nil : text
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let app = SourceApp(bundleURL: url) else { return }
        if !apps.contains(app) { apps.insert(app, at: 0) }
        rule.sourceApp = app
    }
}

extension Space {
    /// The name, after the icon when it has one.
    var label: String {
        [icon, name].compactMap { $0 }.joined(separator: " ")
    }
}
