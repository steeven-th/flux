import SwiftUI

/// The service pages are translated with, and the user's key for it.
struct TranslationSettings: View {
    @Bindable var state: BrowserState

    @State private var key = ""
    @State private var result: String?
    @State private var isTesting = false

    var body: some View {
        let provider = state.translationProvider
        Section {
            Picker("Service", selection: $state.translationProvider) {
                ForEach(TranslationProvider.allCases) { provider in
                    Text(verbatim: provider.name).tag(provider)
                }
            }
            SecureField("API key", text: $key)
                .onChange(of: key) {
                    TranslationKeychain.setKey(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
                    PageTranslator.shared.configure(provider)
                    result = nil
                }
            LabeledContent {
                HStack {
                    if let result {
                        Text(result).foregroundStyle(.secondary)
                    }
                    Button("Test") { test(provider) }
                        .disabled(key.isEmpty || isTesting)
                }
            } label: {
                Link("Get a free key…", destination: provider.keyPage)
            }
        } header: {
            Text("Page Translation")
        } footer: {
            Text("Pages you translate are sent to \(provider.name). Selected text is translated by macOS.")
                .foregroundStyle(.secondary)
        }
        .onAppear { key = TranslationKeychain.key(for: provider) ?? "" }
        .onChange(of: state.translationProvider) {
            key = TranslationKeychain.key(for: state.translationProvider) ?? ""
            result = nil
        }
    }

    /// Translates a word, then shows what the key has left this month.
    private func test(_ provider: TranslationProvider) {
        let service = provider.service(key: key.trimmingCharacters(in: .whitespacesAndNewlines))
        isTesting = true
        Task {
            defer { isTesting = false }
            do {
                _ = try await service.translate(["Hello"], into: PageTranslator.targetLanguage)
                let usage = try await service.usage()
                let used = usage?.used ?? state.translatedCharactersThisMonth
                let limit = usage?.limit ?? provider.freeCharacters ?? 0
                result = String(localized: "Works. \(used.formatted()) of \(limit.formatted()) characters used this month.")
            } catch {
                result = error.localizedDescription
            }
        }
    }
}
