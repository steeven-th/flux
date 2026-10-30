/// The page's side of translation. It hands out the page's texts, puts translations in their
/// place and keeps the originals, and watches for texts the page adds later.
enum PageTranslationScript {
    /// Installs the script if the page doesn't have it yet, then returns the texts not handed out
    /// yet as JSON: all of the page's the first time, then those it added or changed since.
    static let next = install + "window.__fluxTranslation.next()"

    /// `translations` is a JSON object of translated texts by id.
    static func apply(_ translations: String) -> String {
        "window.__fluxTranslation && window.__fluxTranslation.apply(\(translations))"
    }

    static let restore = "window.__fluxTranslation && window.__fluxTranslation.restore()"

    /// The page's declared language and the start of its text, as JSON.
    static let sample = """
        JSON.stringify({ lang: document.documentElement.lang || '', text: (document.body ? document.body.innerText : '').slice(0, 3000) })
        """

    private static let install = #"""
        (() => {
          if (window.__fluxTranslation) return;
          // Code, fields and what the page marks as not to translate keep their text.
          const skipped = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'CODE', 'PRE', 'KBD', 'SAMP', 'VAR',
            'TEXTAREA', 'INPUT', 'SELECT', 'OPTION', 'SVG', 'MATH', 'CANVAS', 'IFRAME']);
          const letter = /\p{L}/u;
          const state = { nodes: new Map(), originals: new Map(), handedOut: new WeakSet(), nextID: 0,
            changed: new Set(), started: false, applying: false, observer: null };

          function accepts(node) {
            if (node.data.trim().length < 2 || !letter.test(node.data)) return false;
            const parent = node.parentElement;
            if (!parent || parent.closest('[translate="no"], .notranslate, [contenteditable=""], [contenteditable="true"]')) return false;
            for (let element = parent; element; element = element.parentElement) {
              if (skipped.has(element.tagName.toUpperCase())) return false;
            }
            return true;
          }

          function collect(root) {
            if (root.nodeType === Node.TEXT_NODE) return !state.handedOut.has(root) && accepts(root) ? [root] : [];
            if (root.nodeType !== Node.ELEMENT_NODE) return [];
            const found = [];
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
              if (!state.handedOut.has(node) && accepts(node)) found.push(node);
            }
            return found;
          }

          // What is on screen first, then what is below it, then what was scrolled past.
          function handOut(nodes) {
            const height = window.innerHeight;
            const rank = (node) => {
              const box = node.parentElement.getBoundingClientRect();
              return box.bottom >= 0 && box.top <= height ? 0 : box.top > height ? 1 : 2;
            };
            return nodes
              .map((node, index) => [node, rank(node), index])
              .sort((a, b) => a[1] - b[1] || a[2] - b[2])
              .map(([node]) => {
                state.handedOut.add(node);
                const id = state.nextID++;
                state.nodes.set(id, node);
                return { id, text: node.data };
              });
          }

          function observe() {
            state.observer = new MutationObserver((records) => {
              for (const record of records) {
                if (record.type === 'characterData') {
                  // The page changed a text: its new text is the one to keep and translate.
                  if (state.originals.has(record.target)) state.originals.set(record.target, record.target.data);
                  state.handedOut.delete(record.target);
                  state.changed.add(record.target);
                } else {
                  record.addedNodes.forEach((node) => state.changed.add(node));
                }
              }
            });
            state.observer.observe(document.body, { childList: true, subtree: true, characterData: true });
          }

          window.__fluxTranslation = {
            next() {
              if (!document.body) return '[]';
              if (!state.started) {
                state.started = true;
                observe();
                return JSON.stringify(handOut(collect(document.body)));
              }
              const nodes = [];
              for (const root of state.changed) {
                if (root.isConnected) nodes.push(...collect(root));
              }
              state.changed.clear();
              return JSON.stringify(handOut(nodes));
            },
            apply(translations) {
              for (const [id, text] of Object.entries(translations)) {
                const node = state.nodes.get(Number(id));
                state.nodes.delete(Number(id));
                if (!node || !node.isConnected) continue;
                if (!state.originals.has(node)) state.originals.set(node, node.data);
                // Translations lose the spaces around the text, which the layout may need.
                const before = node.data.match(/^\s*/)[0];
                const after = node.data.match(/\s*$/)[0];
                node.data = before + text.trim() + after;
              }
              // Flux's own changes are not the page's.
              if (state.observer) state.observer.takeRecords();
              return true;
            },
            restore() {
              if (state.observer) state.observer.disconnect();
              for (const [node, text] of state.originals) node.data = text;
              delete window.__fluxTranslation;
              return true;
            },
          };
        })();
        """#
}
