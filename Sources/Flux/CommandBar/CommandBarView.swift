import SwiftUI

struct CommandBarView: View {
    private static let fieldHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 2
    private static let listPadding: CGFloat = 8

    /// The panel sizes itself from this, so it has to match the layout below.
    static func height(forRows rows: Int) -> CGFloat {
        guard rows > 0 else { return fieldHeight }
        return fieldHeight + 1 + 2 * listPadding + CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }

    @Bindable var model: CommandBarModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search or Enter URL…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isFieldFocused)
            }
            .padding(.horizontal, 16)
            .frame(height: Self.fieldHeight)

            if !model.suggestions.isEmpty {
                Divider()
                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            searchEngineName: model.state.searchEngine.name,
                            favicon: model.favicon(for: suggestion),
                            isSelected: index == model.selectedIndex,
                            tint: model.state.selectedSpace.color
                        )
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                        .onHover { if $0 { model.select(index) } }
                        .onTapGesture {
                            model.select(index)
                            model.performSelected()
                        }
                    }
                }
                .padding(Self.listPadding)
            }
            Spacer(minLength: 0)
        }
        .onAppear { isFieldFocused = true }
    }
}

private struct SuggestionRow: View {
    let suggestion: CommandBarModel.Suggestion
    let searchEngineName: String
    let favicon: NSImage?
    let isSelected: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 18, height: 18)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(action)
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Image(systemName: "arrow.right")
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .tertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? tint.opacity(0.3) : .clear))
    }

    @ViewBuilder private var icon: some View {
        switch suggestion {
        case .tab(let tab):
            if let favicon = tab.favicon {
                Image(nsImage: favicon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        case .page:
            if let favicon {
                Image(nsImage: favicon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "clock").foregroundStyle(.secondary)
            }
        case .url:
            Image(systemName: "globe").foregroundStyle(.secondary)
        case .search:
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch suggestion {
        case .tab(let tab): tab.displayTitle
        case .page(let page): page.title.isEmpty ? page.url : page.title
        case .url(let url): url
        case .search(let query): query
        }
    }

    private var action: String {
        switch suggestion {
        case .tab: "Switch to Tab"
        case .page, .url: "Open"
        case .search: "Search \(searchEngineName)"
        }
    }
}
