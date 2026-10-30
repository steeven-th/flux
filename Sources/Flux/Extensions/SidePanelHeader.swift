import SwiftUI

/// The bar over an extension's side panel, as in Chrome: whose panel it is, and a way to close it.
struct SidePanelHeader: View {
    let state: BrowserState
    let tab: Tab

    static let height: CGFloat = 32

    var body: some View {
        let item = tab.sidePanelExtensionID.flatMap { id in
            state.extensions(inSpace: tab.spaceID).first { $0.id == id }
        }
        HStack(spacing: 6) {
            if let icon = item?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }
            Text(verbatim: item?.name ?? "")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                tab.closeSidePanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .symbolRenderingMode(.monochrome)
        .background(.background)
        .overlay(alignment: .bottom) { Divider() }
    }
}
