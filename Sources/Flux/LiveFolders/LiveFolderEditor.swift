import SwiftUI

/// Makes a live folder, or changes where an existing one's tabs come from.
struct LiveFolderEditor: View {
    let state: BrowserState
    let folder: Folder?
    let onDone: () -> Void

    @State private var kind: LiveSource.Kind
    @State private var address: String
    @State private var search: GitHubSearch?
    @State private var customSearch: String
    @State private var name: String
    @State private var isChecking = false
    @State private var error: String?
    private let github = GitHubAccount.shared

    init(state: BrowserState, folder: Folder?, onDone: @escaping () -> Void) {
        self.state = state
        self.folder = folder
        self.onDone = onDone
        let source = folder?.liveSource
        _kind = State(initialValue: source?.kind ?? .feed)
        _address = State(initialValue: source?.kind == .feed ? source?.value ?? "" : "")
        let preset = source.flatMap { $0.kind == .github ? GitHubSearch(rawValue: $0.value) : nil }
        _search = State(initialValue: source?.kind == .github ? preset : .reviewRequested)
        _customSearch = State(initialValue: source?.kind == .github && preset == nil ? source?.value ?? "" : "")
        _name = State(initialValue: folder?.title ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(folder == nil ? "New Live Folder" : "Edit Live Folder").font(.headline)
            Text("Its tabs come from a feed or a GitHub search, and update by themselves every 30 minutes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Source", selection: $kind) {
                Text("RSS or Atom Feed").tag(LiveSource.Kind.feed)
                Text("GitHub").tag(LiveSource.Kind.github)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind {
            case .feed:
                TextField("Feed or site address", text: $address)
                    .textFieldStyle(.roundedBorder)
                Text("A site's address works too, when its pages name their feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .github:
                githubFields
            }

            TextField("Name", text: $name, prompt: Text(defaultName))
                .textFieldStyle(.roundedBorder)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isChecking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel, action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button(folder == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isChecking)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder private var githubFields: some View {
        if !github.isAvailable {
            Text("This build of Flux can't sign in to GitHub.")
                .foregroundStyle(.secondary)
        } else if let code = github.deviceCode {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type this code on the GitHub page that opened. It is copied already.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(verbatim: code.userCode)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.userCode, forType: .string)
                    }
                    ProgressView().controlSize(.small)
                    Spacer()
                    Button("Cancel") { github.cancelSignIn() }
                }
            }
        } else if !github.isSignedIn {
            HStack {
                Button("Sign In to GitHub…") { github.signIn() }
                if let error = github.signInError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Picker("Search", selection: $search) {
                ForEach(GitHubSearch.allCases) { Text($0.name).tag(GitHubSearch?.some($0)) }
                Divider()
                Text("Custom Search").tag(GitHubSearch?.none)
            }
            if search == nil {
                TextField("is:open is:pr repo:owner/name", text: $customSearch)
                    .textFieldStyle(.roundedBorder)
                Text("As in GitHub's search, @me standing for you. Open ones only, unless it says is:closed or is:merged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(github.login.map { String(localized: "Signed in as \($0)") } ?? String(localized: "Signed in to GitHub"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Sign Out") { github.signOut() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private var sourceValue: String {
        kind == .feed ? address.trimmingCharacters(in: .whitespaces) : githubQuery
    }

    private var githubQuery: String {
        search?.rawValue ?? customSearch.trimmingCharacters(in: .whitespaces)
    }

    private var defaultName: String {
        switch kind {
        case .feed: URL(string: address)?.host() ?? String(localized: "Live Folder")
        case .github: search.map { String(localized: $0.name) } ?? String(localized: "GitHub")
        }
    }

    private var canSave: Bool {
        switch kind {
        case .feed: URL(string: address.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
        case .github: github.isSignedIn && !githubQuery.isEmpty
        }
    }

    private func save() {
        var typedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A new source names the folder, unless the user renamed it here.
        if let folder, typedName == folder.title, folder.liveSource?.value != sourceValue { typedName = "" }
        switch kind {
        case .github:
            finish(LiveSource(kind: .github, value: githubQuery), name: typedName.isEmpty ? defaultName : typedName)
        case .feed:
            // Checked first, for its title and its own address when a site's was typed.
            isChecking = true
            error = nil
            Task {
                defer { isChecking = false }
                do {
                    let feed = try await FeedReader.feed(at: address)
                    finish(LiveSource(kind: .feed, value: feed.url), name: typedName.isEmpty ? feed.title ?? defaultName : typedName)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func finish(_ source: LiveSource, name: String) {
        if let folder {
            state.setLiveSource(source, title: name, of: folder)
        } else {
            state.createLiveFolder(title: name, source: source)
        }
        onDone()
    }
}
