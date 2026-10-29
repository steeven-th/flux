import SwiftUI

struct LinkSettings: View {
    let state: BrowserState

    @State private var linkTargetsOpenPeek = true
    @State private var shiftClickOpensPeek = true

    var body: some View {
        Form {
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
        .onAppear {
            linkTargetsOpenPeek = state.linkTargetsOpenPeek
            shiftClickOpensPeek = state.shiftClickOpensPeek
        }
        .onChange(of: linkTargetsOpenPeek) { state.linkTargetsOpenPeek = linkTargetsOpenPeek }
        .onChange(of: shiftClickOpensPeek) { state.shiftClickOpensPeek = shiftClickOpensPeek }
    }
}
