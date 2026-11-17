import Foundation

/// A site's own style sheet and script, and the elements the user zapped off its pages, in every
/// space, as Arc's Boosts. They run in an isolated world, as an extension's content scripts do, so
/// the page can't read or change them.
struct Boost: Codable, Equatable {
    var css = ""
    var js = ""
    var zapped: [String] = []

    var isEmpty: Bool {
        css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && js.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && zapped.isEmpty
    }
}

@MainActor
@Observable
final class Boosts {
    static let shared = Boosts()

    private static let settingKey = "boosts"

    @ObservationIgnored private var database: AppDatabase?
    /// By host: www.example.com and example.com are boosted apart.
    private(set) var boosts: [String: Boost] = [:]

    func start(database: AppDatabase) {
        self.database = database
        boosts = (try? database.setting(Self.settingKey))
            .flatMap { try? JSONDecoder().decode([String: Boost].self, from: Data($0.utf8)) } ?? [:]
    }

    func boost(forHost host: String) -> Boost {
        boosts[host.lowercased()] ?? Boost()
    }

    func set(_ boost: Boost, forHost host: String) {
        boosts[host.lowercased()] = boost.isEmpty ? nil : boost
        save()
    }

    func zap(_ selector: String, onHost host: String) {
        var boost = boost(forHost: host)
        guard !selector.isEmpty, !boost.zapped.contains(selector) else { return }
        boost.zapped.append(selector)
        set(boost, forHost: host)
    }

    private func save() {
        let json = boosts.isEmpty ? nil : (try? JSONEncoder().encode(boosts)).flatMap { String(data: $0, encoding: .utf8) }
        try? database?.setSetting(Self.settingKey, to: json)
    }

    /// The site's style sheet, zapped elements included, then its script once the page is parsed.
    func script(forHost host: String) -> String? {
        let boost = boost(forHost: host)
        guard !boost.isEmpty else { return nil }
        let hidden = boost.zapped.map { "\($0) { display: none !important; }" }
        let css = ([boost.css] + hidden).filter { !$0.isEmpty }.joined(separator: "\n")
        guard let style = Self.jsonLiteral(css), let script = Self.jsonLiteral(boost.js) else { return nil }
        return """
        (() => {
          const style = \(style);
          if (style) {
            const sheet = document.createElement('style');
            sheet.textContent = style;
            (document.head || document.documentElement).appendChild(sheet);
          }
          const script = \(script);
          if (!script.trim()) return;
          const run = () => {
            try { (0, eval)(script); } catch (error) { console.error('Boost:', error); }
          };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run, { once: true });
          else run();
        })();
        """
    }

    private static func jsonLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Outlines the element under the pointer. A click hides it and reports a selector that finds
    /// it again, through the page's start script (FLXBrowserView), until Escape or Done.
    static func zapperScript(hint: String, done: String) -> String {
        let hint = jsonLiteral(hint) ?? "''"
        let done = jsonLiteral(done) ?? "''"
        return #"""
        (() => {
          if (window.__fluxZapperStop) return;
          const root = document.documentElement;
          const box = document.createElement('div');
          box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #ff3b30;background:rgba(255,59,48,0.15);border-radius:3px;display:none';
          const bar = document.createElement('div');
          bar.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;display:flex;gap:12px;align-items:center;padding:8px 8px 8px 14px;border-radius:10px;background:rgba(30,30,30,0.92);color:#fff;font:13px -apple-system,sans-serif;box-shadow:0 6px 20px rgba(0,0,0,0.3)';
          const label = document.createElement('span');
          label.textContent = \#(hint);
          const button = document.createElement('button');
          button.textContent = \#(done);
          button.style.cssText = 'font:inherit;padding:4px 12px;border:0;border-radius:6px;background:#fff;color:#000;cursor:pointer';
          bar.append(label, button);
          root.append(box, bar);
          let target = null;
          const ours = (element) => element === bar || bar.contains(element) || element === box;
          const selectorFor = (element) => {
            const parts = [];
            for (let node = element; node && node.nodeType === 1 && node !== root; node = node.parentElement) {
              if (node.id && !/\d{3,}/.test(node.id)) { parts.unshift('#' + CSS.escape(node.id)); break; }
              let part = node.localName;
              const classes = [...node.classList].filter((name) => !/\d/.test(name)).slice(0, 2);
              part += classes.map((name) => '.' + CSS.escape(name)).join('');
              const parent = node.parentElement;
              if (parent) {
                const same = [...parent.children].filter((child) => child.localName === node.localName);
                if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(node) + 1) + ')';
              }
              parts.unshift(part);
              const selector = parts.join(' > ');
              try { if (document.querySelectorAll(selector).length === 1) return selector; } catch {}
            }
            return parts.join(' > ');
          };
          const move = (event) => {
            const element = document.elementFromPoint(event.clientX, event.clientY);
            if (!element || ours(element) || element === root || element === document.body) {
              box.style.display = 'none';
              target = null;
              return;
            }
            target = element;
            // Kept within the page, whose corners Flux rounds (FLXPageCornerRadius, 18 points).
            const rect = element.getBoundingClientRect();
            const left = Math.max(rect.left, 2), top = Math.max(rect.top, 2);
            const right = Math.min(rect.right, innerWidth - 2), bottom = Math.min(rect.bottom, innerHeight - 2);
            Object.assign(box.style, {
              display: 'block', left: left + 'px', top: top + 'px',
              width: Math.max(right - left, 0) + 'px', height: Math.max(bottom - top, 0) + 'px',
              borderTopLeftRadius: (left <= 2 && top <= 2) ? '16px' : '3px',
              borderTopRightRadius: (right >= innerWidth - 2 && top <= 2) ? '16px' : '3px',
              borderBottomLeftRadius: (left <= 2 && bottom >= innerHeight - 2) ? '16px' : '3px',
              borderBottomRightRadius: (right >= innerWidth - 2 && bottom >= innerHeight - 2) ? '16px' : '3px',
            });
          };
          const click = (event) => {
            if (ours(event.target)) return;
            event.preventDefault();
            event.stopPropagation();
            if (!target) return;
            const selector = selectorFor(target);
            target.style.setProperty('display', 'none', 'important');
            box.style.display = 'none';
            root.setAttribute('data-flux-zap', selector);
            document.dispatchEvent(new Event('flux-zap'));
          };
          const key = (event) => { if (event.key === 'Escape') stop(); };
          const stop = () => {
            document.removeEventListener('mousemove', move, true);
            document.removeEventListener('click', click, true);
            document.removeEventListener('keydown', key, true);
            box.remove();
            bar.remove();
            delete window.__fluxZapperStop;
          };
          button.addEventListener('click', stop);
          document.addEventListener('mousemove', move, true);
          document.addEventListener('click', click, true);
          document.addEventListener('keydown', key, true);
          window.__fluxZapperStop = stop;
        })();
        """#
    }
}

/// What runs in a page as it starts and reports what it holds: content blocking's element hiding,
/// and the site's Boost.
@MainActor
enum PageScripts {
    static func install() {
        FLXBrowserView.pageScriptProvider = { host, message, blocksContent in
            MainActor.assumeIsolated { script(forHost: host, message: message, blocksContent: blocksContent) }
        }
    }

    private static func script(forHost host: String, message: String, blocksContent: Bool) -> String? {
        if message.hasPrefix("zap:") {
            Boosts.shared.zap(String(message.dropFirst(4)), onHost: host)
            return nil
        }
        var scripts: [String] = []
        if blocksContent, let hiding = ContentBlocker.shared.hiding?.script(forHost: host, message: message) {
            scripts.append(hiding)
        }
        if message.isEmpty, let boost = Boosts.shared.script(forHost: host) {
            scripts.append(boost)
        }
        return scripts.isEmpty ? nil : scripts.joined(separator: "\n")
    }
}
