import Foundation
import Kadr

extension Caption {

    /// Load and parse a caption file from disk, dispatching to the format-specific
    /// parser by file extension. Recognized extensions (case-insensitive): `.srt`,
    /// `.vtt`. Throws ``CaptionParseError/unrecognizedFormat(extension:)`` for any
    /// other extension.
    ///
    /// ```swift
    /// let cues = try await Caption.load(subtitleURL)  // either .srt or .vtt
    /// video.captions(cues)
    /// ```
    public static func load(_ url: URL) async throws -> [Caption] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "srt":
            return try await load(srt: url)
        case "vtt":
            return try await load(vtt: url)
        default:
            throw CaptionParseError.unrecognizedFormat(extension: ext)
        }
    }
}
