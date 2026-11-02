import Foundation

/// What a page plays, as its frames report it.
struct TabMedia: Equatable {
    var isPlaying: Bool
    /// From the site's media session. Empty when the site gives none.
    var title: String
    var artist: String
    var hasPrevious: Bool
    var hasNext: Bool
    /// The page's own volume, from 0 to 1.
    var volume: Double

    init(_ media: [String: Any]) {
        isPlaying = media["playing"] as? Bool ?? false
        title = media["title"] as? String ?? ""
        artist = media["artist"] as? String ?? ""
        hasPrevious = media["previous"] as? Bool ?? false
        hasNext = media["next"] as? Bool ?? false
        volume = media["volume"] as? Double ?? 1
    }
}

enum MediaCommand {
    case play, pause, previous, next
    case volume(Double)
}
