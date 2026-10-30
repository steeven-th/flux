import Foundation

/// A width range from the page's media queries, in CSS pixels.
struct MediaQuery: Hashable {
    enum Kind: CaseIterable {
        case max, range, min
    }

    let min: Double?
    let max: Double?

    var kind: Kind {
        switch (min, max) {
        case (nil, _): .max
        case (_, nil): .min
        default: .range
        }
    }

    /// The width a click on its bar gives the page.
    var width: Int {
        Int((max ?? min ?? 0).rounded())
    }

    func contains(_ width: Double) -> Bool {
        (min.map { width >= $0 } ?? true) && (max.map { width <= $0 } ?? true)
    }

    var text: String {
        [min.map { "(min-width: \(Int($0))px)" }, max.map { "(max-width: \(Int($0))px)" }]
            .compactMap { $0 }
            .joined(separator: " and ")
    }

    /// From the result of the protocol's CSS.getMediaQueries. Lengths come computed in pixels,
    /// whatever unit the stylesheet used.
    static func parse(_ result: [AnyHashable: Any]?) -> [MediaQuery] {
        let medias = result?["medias"] as? [[String: Any]] ?? []
        var queries = Set<MediaQuery>()
        for media in medias {
            for query in media["mediaList"] as? [[String: Any]] ?? [] {
                var min: Double?
                var max: Double?
                for expression in query["expressions"] as? [[String: Any]] ?? [] {
                    guard let length = expression["computedLength"] as? Double, length > 0 else { continue }
                    switch expression["feature"] as? String {
                    case "min-width": min = length
                    case "max-width": max = length
                    default: break
                    }
                }
                if min != nil || max != nil { queries.insert(MediaQuery(min: min, max: max)) }
            }
        }
        return queries.sorted { ($0.max ?? $0.min ?? 0) > ($1.max ?? $1.min ?? 0) }
    }
}
