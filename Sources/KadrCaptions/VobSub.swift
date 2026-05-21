import Foundation
import CoreMedia
import Kadr

/// Index of a VobSub (image-based DVD subtitle) file. v0.6.
///
/// VobSub subtitles ship as a pair of files — a textual `.idx` index and a
/// binary `.sub` blob containing run-length-encoded bitmap glyphs at byte
/// offsets the index references. We parse only the `.idx` (timing + palette
/// + file offsets) and leave bitmap extraction to a future cycle — kadr-captions
/// today is a parser library, not a rasterizer.
///
/// **Why surface this at all if we don't OCR the text?** Real ingest pipelines
/// hit `.idx`/`.sub` files in archived DVD rips. Telling the consumer
/// "subtitles exist here, here's *when*" lets them either (a) drop placeholder
/// `Caption` entries to mark subtitle-existence, or (b) hand the file off to
/// a separate VobSub-aware renderer once we expose the bitmaps in v0.7.
///
/// The struct is intentionally opaque about the rendering — `paletteHex` is
/// surfaced for inspection but consumers shouldn't construct one without
/// reading from an `.idx` file. The parser is the only sanctioned producer.
public struct VobSubIndex: Sendable, Equatable {

    /// Two-letter ISO language tag (e.g. `"en"`, `"de"`) declared at the top
    /// of the `.idx` file via the `id:` field. `nil` when the `.idx` omits
    /// the language declaration (rare but legal).
    public let language: String?

    /// 16-entry color palette declared at the top of the file. Each entry is
    /// a 6-hex-digit RGB string (no `#` prefix), matching the `.idx` file's
    /// `palette:` line format. Always exactly 16 entries when present — the
    /// parser pads with `"000000"` if the file declares fewer, and truncates
    /// if more, so consumers can index without bounds-checking.
    ///
    /// `nil` when the `.idx` file has no `palette:` line — defensible
    /// behavior for malformed files; downstream rasterizers can substitute
    /// their own palette.
    public let paletteHex: [String]?

    /// One entry per `timestamp: ... , filepos: ...` line. Sorted by start
    /// time (the `.idx` format requires monotonic timestamps; we don't
    /// re-sort, but we also don't assume the file is malformed).
    public let cues: [VobSubCue]

    public init(language: String?, paletteHex: [String]?, cues: [VobSubCue]) {
        self.language = language
        self.paletteHex = paletteHex
        self.cues = cues
    }
}

/// One cue inside a `VobSubIndex`. v0.6.
///
/// Carries the timing (when the bitmap should appear on screen) and the byte
/// offset into the paired `.sub` file (where the run-length-encoded bitmap
/// data lives). The actual bitmap extraction is out of scope for this
/// release — consumers either route through a separate VobSub renderer or
/// wait for the v0.7 follow-up.
public struct VobSubCue: Sendable, Equatable {

    /// Composition-time start. `.idx` files always include this; the parser
    /// rejects entries without a valid timestamp.
    public let start: CMTime

    /// Byte offset into the paired `.sub` file where this cue's RLE bitmap
    /// begins. Surfaced as `Int` rather than `UInt32` for ergonomic interop
    /// with `Data.subdata(in:)` and `FileHandle.seek(toOffset:)`.
    public let fileOffset: Int

    public init(start: CMTime, fileOffset: Int) {
        self.start = start
        self.fileOffset = fileOffset
    }
}

extension CaptionParser {

    /// Parse the textual `.idx` half of a VobSub pair. Tolerates whitespace
    /// and comment lines (starting with `#`); rejects entries with
    /// malformed timestamps or unparseable `filepos:` offsets.
    ///
    /// The `.idx` format is line-oriented and case-sensitive on the field
    /// names. Recognized lines:
    /// - `id: <lang>, index: <n>` — language declaration; the parser keeps
    ///   the language and ignores the index (multi-language `.idx` files
    ///   are out of scope for v0.6; consumers wanting per-language streams
    ///   pre-split the file).
    /// - `palette: <hex>, <hex>, ...` — comma-separated 6-hex-digit RGB
    ///   entries. Padded / truncated to exactly 16.
    /// - `timestamp: HH:MM:SS:mmm, filepos: 0xHEX` — one cue per line.
    ///   Hex prefix is required.
    ///
    /// Everything else (id-line `index:` field, `size:`, `org:`,
    /// `scale:`, etc.) is skipped silently. v0.6 doesn't surface layout
    /// metadata — those become relevant once we render the bitmap.
    public static func parseVobSubIndex(_ content: String) throws -> VobSubIndex {
        var language: String?
        var paletteHex: [String]?
        var cues: [VobSubCue] = []

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("id:") {
                language = parseVobSubLanguage(line)
            } else if line.hasPrefix("palette:") {
                paletteHex = parseVobSubPalette(line)
            } else if line.hasPrefix("timestamp:") {
                guard let cue = parseVobSubCueLine(line) else {
                    throw CaptionParseError.malformedTimestamp(line: index + 1, raw: line)
                }
                cues.append(cue)
            }
            // Other directives intentionally ignored.
        }

        return VobSubIndex(language: language, paletteHex: paletteHex, cues: cues)
    }

    /// Pure: extract the two-letter language tag from an `id:` line.
    /// `id: en, index: 0` → `"en"`. Returns nil when the value is empty
    /// or longer than 8 chars (defensive — real values are 2 chars).
    public static func parseVobSubLanguage(_ line: String) -> String? {
        // Strip the `id:` prefix and the optional `, index: N` suffix.
        let payload = line.dropFirst("id:".count)
        let firstSegment = payload.split(separator: ",").first ?? ""
        let trimmed = firstSegment.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 8 else { return nil }
        return trimmed
    }

    /// Pure: extract the palette from a `palette:` line. Pads to 16 with
    /// `"000000"` or truncates as needed.
    public static func parseVobSubPalette(_ line: String) -> [String]? {
        let payload = line.dropFirst("palette:".count)
        let entries = payload
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count == 6 && $0.allSatisfy(\.isHexDigit) }
        if entries.isEmpty { return nil }
        var padded = entries
        while padded.count < 16 { padded.append("000000") }
        if padded.count > 16 { padded = Array(padded.prefix(16)) }
        return padded
    }

    /// Pure: parse one `timestamp: ... , filepos: 0x...` line.
    /// Returns nil for malformed input; the caller wraps as a parse error
    /// with line context.
    static func parseVobSubCueLine(_ line: String) -> VobSubCue? {
        // Format: timestamp: HH:MM:SS:mmm, filepos: 0xHEX
        let payload = line.dropFirst("timestamp:".count)
        let parts = payload.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let stampRaw = parts[0].trimmingCharacters(in: .whitespaces)
        let fileposRaw = parts[1].trimmingCharacters(in: .whitespaces)

        guard let start = parseVobSubTimestamp(stampRaw) else { return nil }
        guard let offset = parseVobSubFilepos(fileposRaw) else { return nil }
        return VobSubCue(start: start, fileOffset: offset)
    }

    /// Pure: convert a `HH:MM:SS:mmm` timestamp to `CMTime`. Distinct from
    /// SRT's comma separator + VTT's dot. Time-scale 1000 since the field
    /// is millisecond-precision.
    public static func parseVobSubTimestamp(_ raw: String) -> CMTime? {
        let parts = raw.split(separator: ":")
        guard parts.count == 4 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]),
              let s = Int(parts[2]), let ms = Int(parts[3]) else { return nil }
        let totalMillis = ((h * 3600) + (m * 60) + s) * 1000 + ms
        return CMTime(value: CMTimeValue(totalMillis), timescale: 1000)
    }

    /// Pure: parse a `filepos: 0xHEX` field. Requires the `0x` prefix
    /// (matches the format spec; bare-hex offsets aren't valid VobSub).
    static func parseVobSubFilepos(_ raw: String) -> Int? {
        let prefix = "filepos:"
        guard raw.hasPrefix(prefix) else { return nil }
        let value = raw.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("0x") || value.hasPrefix("0X") else { return nil }
        return Int(value.dropFirst(2), radix: 16)
    }
}

extension Caption {

    /// Convenience: render a `VobSubIndex` as `[Caption]` with placeholder
    /// text. The cue duration is inferred as the gap to the next cue (the
    /// `.idx` format doesn't carry an end time — a cue stays on-screen
    /// until the next one displaces it, with a default 5s fallback for the
    /// last cue since the file gives us nothing).
    ///
    /// Use this when the consumer wants to *mark* subtitle existence in the
    /// project without actually rendering bitmap glyphs — e.g. surfacing an
    /// "[image subtitle]" badge in the timeline editor. Bitmap extraction
    /// is v0.7. v0.6.
    public static func fromVobSubIndex(
        _ index: VobSubIndex,
        placeholderText: String = "",
        trailingDuration: CMTime = CMTime(value: 5000, timescale: 1000)
    ) -> [Caption] {
        var result: [Caption] = []
        for (i, cue) in index.cues.enumerated() {
            let endTime: CMTime
            if i + 1 < index.cues.count {
                endTime = index.cues[i + 1].start
            } else {
                endTime = cue.start + trailingDuration
            }
            let duration = endTime - cue.start
            result.append(Caption(
                text: placeholderText,
                timeRange: CMTimeRange(start: cue.start, duration: duration)
            ))
        }
        return result
    }
}

private extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
