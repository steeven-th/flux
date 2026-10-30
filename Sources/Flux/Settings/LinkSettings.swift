import SwiftUI

struct LinkSettings: View {
    let state: BrowserState

    @State private var linkTargetsOpenPeek = true
    @State private var shiftClickOpensPeek = true
    @State private var outsideLinksOpenLittleWindow = true
    @State private var rules: [LinkRule] = []
    @State private var editedRule: LinkRule?

    var body: some View {
        Form {
            Section {
                Picker("Open links from other apps in", selection: $outsideLinksOpenLittleWindow) {
                    Text("A little window").tag(true)
                    Text("A new tab of the current space").tag(false)
                }
            } footer: {
                Text("A little window shows the page on its own. Browse there and close it, or move the page to a space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(rules) { rule in
                    LinkRuleRow(state: state, rule: rule, edit: { editedRule = rule }, delete: { delete(rule) })
                        .contextMenu {
                            Button("Move Up") { move(rule, by: -1) }
                                .disabled(rule.id == rules.first?.id)
                            Button("Move Down") { move(rule, by: 1) }
                                .disabled(rule.id == rules.last?.id)
                        }
                }
                HStack {
                    Spacer()
                    Button("Add Rule…") {
                        editedRule = LinkRule(
                            id: UUID(), position: rules.count, urlContains: nil, sourceAppID: nil, sourceAppName: nil,
                            spaceID: state.selectedSpaceID, opensLittleWindow: false
                        )
                    }
                }
            } header: {
                Text("Rules for links from other apps")
            } footer: {
                Text("The first rule that matches decides where a link opens. Links no rule matches open as chosen above. Right-click a rule to change its order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open links that open a new tab in Peek", isOn: $linkTargetsOpenPeek)
                Toggle("Open links in Peek with ⇧-click", isOn: $shiftClickOpensPeek)
            } header: {
                Text("Peek shows a link over the page without opening a tab. Keep it as a tab, or close it with ⌘W.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                Text("⌘-click and middle-click always open a tab in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $editedRule) { rule in
            LinkRuleEditor(state: state, rule: rule) { saved in
                if let index = rules.firstIndex(where: { $0.id == saved.id }) {
                    rules[index] = saved
                } else {
                    rules.append(saved)
                }
                state.setLinkRules(rules)
            }
        }
        .onAppear {
            rules = state.linkRules
            linkTargetsOpenPeek = state.linkTargetsOpenPeek
            shiftClickOpensPeek = state.shiftClickOpensPeek
            outsideLinksOpenLittleWindow = state.outsideLinksOpenLittleWindow
        }
        .onChange(of: outsideLinksOpenLittleWindow) { state.outsideLinksOpenLittleWindow = outsideLinksOpenLittleWindow }
        .onChange(of: linkTargetsOpenPeek) { state.linkTargetsOpenPeek = linkTargetsOpenPeek }
        .onChange(of: shiftClickOpensPeek) { state.shiftClickOpensPeek = shiftClickOpensPeek }
    }

    private func delete(_ rule: LinkRule) {
        rules.removeAll { $0.id == rule.id }
        state.setLinkRules(rules)
    }

    private func move(_ rule: LinkRule, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }), rules.indices.contains(index + offset) else { return }
        rules.swapAt(index, index + offset)
        state.setLinkRules(rules)
    }
}
