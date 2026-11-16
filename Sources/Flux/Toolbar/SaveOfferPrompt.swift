import SwiftUI

/// A card, an address or an IBAN a submitted form held, which Chromium offers to keep, under the
/// address in place of Chrome's bubble.
struct SaveOfferPrompt: View {
    let offer: FLXSaveOffer
    let onAnswer: (Bool?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { onAnswer(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(offer.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).textSelection(.enabled)
                    }
                }
            }

            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("No Thanks") { onAnswer(false) }
                Button(offer.isUpdate && offer.kind == .address ? "Update" : "Save") { onAnswer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var title: LocalizedStringKey {
        switch offer.kind {
        case .card: offer.isUpdate ? "Save the security code?" : "Save this card?"
        case .address: offer.isUpdate ? "Update this address?" : "Save this address?"
        case .iban: "Save this IBAN?"
        @unknown default: "Save?"
        }
    }

    private var symbol: String {
        switch offer.kind {
        case .card: "creditcard"
        case .address: "mappin.and.ellipse"
        case .iban: "building.columns"
        @unknown default: "tray.and.arrow.down"
        }
    }

    private var note: LocalizedStringKey {
        "Kept on this Mac, in this space. Flux fills it in for you next time."
    }
}
