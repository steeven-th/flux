import NaturalLanguage
import SwiftUI

/// A page shown translated, and kept so as it changes and as the tab goes to other pages in the
/// same language.
struct PageTranslation: Equatable {
    let source: Locale.Language
    let target: Locale.Language
}

/// Translates pages in place with the service the user has a key for. Pages keep adding text,
/// what loads as you scroll or menus that open, so a translated page is asked for new texts until
/// it is shown in its original language again.
@MainActor
final class PageTranslator {
    static let shared = PageTranslator()

    private var service: TranslationService?
    /// Told how many characters each request sent, for services that don't count them.
    var onCharactersSent: ((Int) -> Void)?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    var isAvailable: Bool { service != nil }

    func configure(_ provider: TranslationProvider) {
        service = TranslationKeychain.key(for: provider).map(provider.service(key:))
    }

    /// The language pages are translated into: the system's, whatever language Flux is shown in.
    static var targetLanguage: Locale.Language {
        let preferred = UserDefaults(suiteName: ".GlobalPreferences")?.stringArray(forKey: "AppleLanguages")?.first
        return Locale.Language(identifier: preferred ?? Locale.preferredLanguages.first ?? "en")
    }

    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode
    }

    /// The text's language, or the one the page declares when there is too little text to tell.
    static func language(ofText text: String, declared: String) -> Locale.Language? {
        if let detected = NLLanguageRecognizer.dominantLanguage(for: text), detected != .undetermined {
            return Locale.Language(identifier: detected.rawValue)
        }
        return declared.isEmpty ? nil : Locale.Language(identifier: declared)
    }

    func start(_ tab: Tab) {
        stop(tab)
        tasks[ObjectIdentifier(tab)] = Task { [weak self, weak tab] in
            while !Task.isCancelled {
                guard let self, let tab, tab.translation != nil else { return }
                await self.translateNewTexts(of: tab)
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func stop(_ tab: Tab) {
        tasks.removeValue(forKey: ObjectIdentifier(tab))?.cancel()
    }

    private struct Item: Decodable {
        let id: Int
        let text: String
    }

    private func translateNewTexts(of tab: Tab) async {
        guard let service, let target = tab.translation?.target,
              let json = await tab.evaluate(PageTranslationScript.next),
              let items = try? JSONDecoder().decode([Item].self, from: Data(json.utf8)), !items.isEmpty else { return }
        tab.setTranslating(true)
        defer { tab.setTranslating(false) }
        // Menus and buttons repeat the same texts: each is sent once, in the order they come,
        // which puts what is on screen first.
        var texts: [String] = []
        var ids: [String: [Int]] = [:]
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if ids[text] == nil { texts.append(text) }
            ids[text, default: []].append(item.id)
        }
        for start in stride(from: 0, to: texts.count, by: service.batchSize) {
            let batch = Array(texts[start..<min(start + service.batchSize, texts.count)])
            do {
                let translations = try await service.translate(batch, into: target)
                onCharactersSent?(batch.reduce(0) { $0 + $1.count })
                var byID: [String: String] = [:]
                for (text, translation) in zip(batch, translations) {
                    for id in ids[text] ?? [] { byID[String(id)] = translation }
                }
                guard tab.translation != nil, let data = try? JSONEncoder().encode(byID) else { return }
                _ = await tab.evaluate(PageTranslationScript.apply(String(decoding: data, as: UTF8.self)))
            } catch is CancellationError {
                return
            } catch {
                tab.translationFailed(error)
                stop(tab)
                return
            }
        }
    }
}

/// Shown while the page is translated: the languages, and the way back to the original.
struct TranslationButton: View {
    let tab: Tab

    var body: some View {
        if let translation = tab.translation {
            Menu {
                Text("Translated from \(Self.name(of: translation.source)) into \(Self.name(of: translation.target))")
                Button("Show Original") { tab.showOriginal() }
            } label: {
                Image(systemName: "translate")
                    .symbolEffect(.pulse, isActive: tab.isTranslating)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Translated Page")
        }
    }

    private static func name(of language: Locale.Language) -> String {
        Locale.current.localizedString(forLanguageCode: language.languageCode?.identifier ?? "") ?? language.minimalIdentifier
    }
}
