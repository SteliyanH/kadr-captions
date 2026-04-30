import Foundation

/// Errors thrown by the SRT / VTT / iTT parsers and file loaders. Carry source-line
/// metadata where applicable so callers can surface "line 42: bad timestamp" without
/// re-scanning the input themselves.
public enum CaptionParseError: Error, Equatable {

    /// File extension didn't match a recognized format. `Caption.load(_:)` only.
    case unrecognizedFormat(extension: String)

    /// A timestamp line failed to parse. `line` is 1-indexed in the source content.
    case malformedTimestamp(line: Int, raw: String)

    /// (Reserved.) An SRT cue index header failed to parse. v0.1 is lenient — the SRT
    /// parser doesn't require a numeric index — so this case is currently unused but
    /// kept in the public surface for forward compatibility (a future strict mode could
    /// surface it).
    case malformedCueIndex(line: Int, raw: String)

    /// WebVTT only — the file didn't start with the required `WEBVTT` header.
    case missingHeader

    /// File I/O failure (file missing, permission denied, etc.).
    case unreadableFile(URL)

    /// File contents couldn't be decoded as either UTF-8 or Windows-1252 (the legacy
    /// SRT fallback). Surfaced when both attempts fail.
    case unsupportedEncoding(URL)
}
