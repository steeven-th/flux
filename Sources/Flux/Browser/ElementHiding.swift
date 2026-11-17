import Foundation

/// The element hiding rules of filter lists, and the scripts that apply them to a page.
///
/// Rules for a site, `example.com##.sponsored`, go in a style sheet as the page starts. Rules for
/// every site, `##.ad-banner`, are tens of thousands: as uBlock Origin does, a page only gets the
/// ones whose class name or id it holds, which it reports as its elements appear. Procedural
/// rules, `example.com#?#.card:has-text(Sponsored)`, run as a script, again as elements appear.
/// Exceptions (`#@#`) take rules out for their sites.
struct ElementHiding: Sendable {
    private var siteSelectors: [String: [String]] = [:]
    private var siteProcedures: [String: [String]] = [:]
    /// Rules for every site, by the class name or id they start with.
    private var genericByToken: [String: [String]] = [:]
    /// Rules for every site that start with neither, which every page gets.
    private var genericOthers: [String] = []
    private var exceptions: [String: Set<String>] = [:]
    /// Rules for every site but these.
    private var genericExclusions: [String: Set<String>] = [:]

    /// Pseudo-classes of uBlock Origin and Adblock Plus that Flux doesn't run.
    private static let unsupported = [
        ":-abp-properties", ":xpath", ":upward", ":matches-css", ":matches-attr", ":matches-path",
        ":min-text-length", ":nth-ancestor", ":remove", ":style(", ":watch-attr", ":others", ":if",
        ":matches-media", ":matches-prop",
    ]
    private static let procedural = [":has-text(", ":-abp-contains(", ":contains(", ":-abp-has("]

    init(lists: [String]) {
        for list in lists {
            for line in list.split(whereSeparator: \.isNewline) {
                add(line)
            }
        }
    }

    private mutating func add(_ line: Substring) {
        guard !line.hasPrefix("!"), !line.hasPrefix("[") else { return }
        let separators = ["#@?#", "#?#", "#@#", "##"]
        guard let (separator, range) = separators.lazy.compactMap({ separator in
            line.range(of: separator).map { (separator, $0) }
        }).min(by: { $0.1.lowerBound < $1.1.lowerBound }) else { return }
        let domains = line[..<range.lowerBound].split(separator: ",").map { $0.lowercased() }
        let included = domains.filter { !$0.hasPrefix("~") }
        let excluded = domains.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
        let selector = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, !selector.hasPrefix("+js"), !selector.hasPrefix("^"),
              !Self.unsupported.contains(where: selector.contains) else { return }
        let isProcedural = separator.contains("?") || Self.procedural.contains(where: selector.contains)

        switch separator {
        case "#@#", "#@?#":
            for domain in included { exceptions[domain, default: []].insert(selector) }
            if included.isEmpty, !isProcedural { genericExclusions[selector, default: []].insert("*") }
        default:
            if included.isEmpty {
                // Procedural rules run per site only, to keep every page light.
                guard !isProcedural else { return }
                addGeneric(selector)
                if !excluded.isEmpty { genericExclusions[selector, default: []].formUnion(excluded) }
            } else {
                for domain in included {
                    if isProcedural {
                        siteProcedures[domain, default: []].append(selector)
                    } else {
                        siteSelectors[domain, default: []].append(selector)
                    }
                }
                for domain in excluded { exceptions[domain, default: []].insert(selector) }
            }
        }
    }

    private mutating func addGeneric(_ selector: String) {
        guard let first = selector.first, first == "." || first == "#" else {
            genericOthers.append(selector)
            return
        }
        let name = selector.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !name.isEmpty else {
            genericOthers.append(selector)
            return
        }
        genericByToken[String(first) + name, default: []].append(selector)
    }

    /// The script for a page's message: an empty one as it starts, then the class names and ids
    /// it holds, as a JSON array.
    func script(forHost host: String, message: String) -> String? {
        let domains = Self.domains(of: host.lowercased())
        let excepted = domains.reduce(into: Set<String>()) { $0.formUnion(exceptions[$1] ?? []) }
        let applies = { (selector: String) in
            guard !excepted.contains(selector) else { return false }
            guard let excluded = genericExclusions[selector] else { return true }
            return !excluded.contains("*") && domains.allSatisfy { !excluded.contains($0) }
        }
        if message.isEmpty {
            let selectors = domains.flatMap { siteSelectors[$0] ?? [] }.filter { !excepted.contains($0) }
                + genericOthers.filter(applies)
            let procedures = domains.flatMap { siteProcedures[$0] ?? [] }.filter { !excepted.contains($0) }
            return [Self.styleScript(selectors), Self.procedureScript(procedures)].compactMap { $0 }.joined(separator: "\n")
        }
        guard let tokens = try? JSONDecoder().decode([String].self, from: Data(message.utf8)) else { return nil }
        return Self.styleScript(tokens.flatMap { genericByToken[$0] ?? [] }.filter(applies))
    }

    /// One rule a selector, so a selector the browser doesn't know only drops its own.
    private static func styleScript(_ selectors: [String]) -> String? {
        var seen = Set<String>()
        let rules = selectors.filter { seen.insert($0).inserted }.map { "\($0) { display: none !important; }" }
        guard !rules.isEmpty, let literal = jsonLiteral(rules.joined(separator: "\n")) else { return nil }
        return """
        (() => {
          const sheet = document.createElement('style');
          sheet.textContent = \(literal);
          (document.head || document.documentElement).appendChild(sheet);
        })();
        """
    }

    private static func procedureScript(_ procedures: [String]) -> String? {
        guard !procedures.isEmpty, let literal = jsonLiteral(procedures) else { return nil }
        return "(\(proceduralRunner))(\(literal));"
    }

    private static func jsonLiteral(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs `css:has-text(text or /regex/)` and `css:has(…)` with procedural parts inside, again
    /// as the page changes. Rules it can't read are skipped.
    private static let proceduralRunner = #"""
    (rules) => {
      const names = { ':has-text(': 'text', ':-abp-contains(': 'text', ':contains(': 'text', ':has(': 'has', ':-abp-has(': 'has' };
      const parse = (source) => {
        let depth = 0, quote = null, css = null, steps = [], i = 0;
        while (i < source.length) {
          const c = source[i];
          if (quote) { if (c === quote) quote = null; i++; continue; }
          if (c === '"' || c === "'") { quote = c; i++; continue; }
          if (c === '(' || c === '[') depth++;
          if (c === ')' || c === ']') depth--;
          const name = depth === 0 && Object.keys(names).find((n) => source.startsWith(n, i));
          if (!name) { if (css !== null) return null; i++; continue; }
          if (css === null) css = source.slice(0, i).trim();
          let level = 1, j = i + name.length;
          for (; j < source.length && level > 0; j++) {
            if (source[j] === '(') level++;
            if (source[j] === ')') level--;
          }
          const argument = source.slice(i + name.length, j - 1);
          if (names[name] === 'text') {
            const regex = argument.match(/^\/(.*)\/([imsu]*)$/);
            steps.push({ text: regex ? new RegExp(regex[1], regex[2]) : argument });
          } else {
            const inner = parse(argument.trim());
            if (!inner) return null;
            steps.push({ has: inner });
          }
          i = j;
        }
        return css === null ? { css: source, steps } : { css, steps };
      };
      const select = (rule, root, relative) => {
        let css = rule.css || '*';
        if (relative && /^[>+~]/.test(css)) css = ':scope ' + css;
        let found;
        try { found = [...root.querySelectorAll(css)]; } catch { return []; }
        return found.filter((element) => rule.steps.every((step) => step.has
          ? select(step.has, element, true).length > 0
          : step.text instanceof RegExp ? step.text.test(element.textContent) : element.textContent.includes(step.text)));
      };
      const parsed = rules.map(parse).filter(Boolean);
      const hide = () => {
        for (const rule of parsed) {
          for (const element of select(rule, document, false)) element.style.setProperty('display', 'none', 'important');
        }
      };
      let timer = null;
      const start = () => {
        hide();
        new MutationObserver(() => { if (!timer) timer = setTimeout(() => { timer = null; hide(); }, 200); })
          .observe(document.documentElement, { childList: true, subtree: true, characterData: true });
      };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
      else start();
    }
    """#

    /// www.example.co.uk gives www.example.co.uk, example.co.uk and co.uk: rules name a domain to
    /// apply to its subdomains too.
    private static func domains(of host: String) -> [String] {
        var parts = host.split(separator: ".")
        var domains: [String] = []
        while parts.count > 1 {
            domains.append(parts.joined(separator: "."))
            parts.removeFirst()
        }
        return domains
    }
}
