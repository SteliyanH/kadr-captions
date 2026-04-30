import Foundation
import CoreMedia
import Kadr

// MARK: - String parser

/// Pure SRT (SubRip) parsing and authoring helpers. File-form variants live on
/// ``Caption`` (parser) and ``CaptionAuthor`` (writer); the string forms here are pure,
/// synchronous, and the testable bulk.
public enum CaptionParser {

    /// Parse SRT content from a pre-loaded string. Lenient about cue indexing — the
    /// parser locates timestamp lines directly and ignores any numeric index that
    /// precedes them, so non-sequential or missing indices in real-world files are
    /// accepted.
    ///
    /// **Line endings.** CRLF, LF, and mixed are all tolerated.
    /// **BOM.** A leading UTF-8 BOM (`\u{FEFF}`) is stripped.
    /// **Cue text.** One or more lines, joined with `\n`. Trailing blank lines stripped.
    /// **Errors.** ``CaptionParseError/malformedTimestamp(line:raw:)`` for unparseable
    /// timestamp lines.
    public static func parseSRT(_ content: String) throws -> [Caption] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .stripUTF8BOM()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var captions: [Caption] = []
        var i = 0
        while i < lines.count {
            // Skip blank and whitespace-only lines and any numeric cue index lines.
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            // If this line contains "-->", it's a timestamp line. Otherwise treat as a
            // cue index (skip) and try the next line.
            let timestampLineIndex: Int
            if lines[i].contains("-->") {
                timestampLineIndex = i
            } else {
                // Assume cue-index line; the timestamp follows.
                timestampLineIndex = i + 1
                if timestampLineIndex >= lines.count {
                    break
                }
            }

            let tsRaw = lines[timestampLineIndex]
            guard let range = parseSRTTimestampLine(tsRaw) else {
                throw CaptionParseError.malformedTimestamp(line: timestampLineIndex + 1, raw: tsRaw)
            }

            // Collect text lines until a blank line or EOF.
            var textLines: [String] = []
            var j = timestampLineIndex + 1
            while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[j])
                j += 1
            }
            let text = textLines.joined(separator: "\n")
            captions.append(Caption(text: text, timeRange: range))
            i = j + 1
        }
        return captions
    }

    /// Parse a single SRT timestamp line of the form `HH:MM:SS,mmm --> HH:MM:SS,mmm`,
    /// returning a `CMTimeRange`. Trailing content after the second timestamp (sometimes
    /// present as positioning hints in non-standard variants) is ignored.
    /// Returns `nil` for unparseable input.
    public static func parseSRTTimestampLine(_ raw: String) -> CMTimeRange? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        let rhsParts = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rhs = rhsParts.first.map(String.init) else { return nil }
        guard let start = parseSRTTimestamp(lhs), let end = parseSRTTimestamp(rhs) else {
            return nil
        }
        let duration = CMTimeSubtract(end, start)
        guard CMTimeCompare(duration, .zero) > 0 else { return nil }
        return CMTimeRange(start: start, duration: duration)
    }

    /// Parse a single SRT timestamp `HH:MM:SS,mmm`. Comma is the SRT decimal separator;
    /// dot is also tolerated for files that mistakenly use VTT-style timestamps.
    public static func parseSRTTimestamp(_ raw: String) -> CMTime? {
        // Accept both "00:01:23,456" and "00:01:23.456" (lenient — some files mix).
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let secParts = parts[2].split(separator: ".")
        guard let s = Int(secParts[0]) else { return nil }
        var ms = 0
        if secParts.count == 2 {
            // Pad / truncate to 3 digits.
            var msStr = String(secParts[1])
            while msStr.count < 3 { msStr += "0" }
            if msStr.count > 3 { msStr = String(msStr.prefix(3)) }
            guard let parsed = Int(msStr) else { return nil }
            ms = parsed
        }
        let total = Double(h * 3600 + m * 60 + s) + Double(ms) / 1000.0
        return CMTime(seconds: total, preferredTimescale: 1000)
    }
}

// MARK: - File loader

extension Caption {

    /// Load and parse an SRT file from disk. UTF-8 default; falls back to Windows-1252
    /// for legacy files (common on older subtitle distributions). Throws
    /// ``CaptionParseError/unreadableFile(_:)`` for I/O failures,
    /// ``CaptionParseError/unsupportedEncoding(_:)`` if both encodings fail, or
    /// ``CaptionParseError/malformedTimestamp(line:raw:)`` for content errors.
    public static func load(srt url: URL) async throws -> [Caption] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CaptionParseError.unreadableFile(url)
        }
        let content: String
        if let utf8 = String(data: data, encoding: .utf8) {
            content = utf8
        } else if let win1252 = String(data: data, encoding: .windowsCP1252) {
            content = win1252
        } else {
            throw CaptionParseError.unsupportedEncoding(url)
        }
        return try CaptionParser.parseSRT(content)
    }
}

// MARK: - Writer

/// Caption file authoring. Counterpart to ``CaptionParser`` — writes an in-memory
/// ``Caption`` array back to disk in the requested format.
public enum CaptionAuthor {

    /// Write captions to disk as SRT. UTF-8 encoded, LF line endings, 1-indexed cue
    /// numbering. Existing file at `url` is overwritten.
    public static func writeSRT(_ captions: [Caption], to url: URL) async throws {
        let content = renderSRT(captions)
        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            throw CaptionParseError.unreadableFile(url)
        }
    }

    /// Render an SRT file body for a list of captions. Pure — exposed for tests and for
    /// callers who want the string form (e.g. to send over the wire instead of writing
    /// to disk).
    public static func renderSRT(_ captions: [Caption]) -> String {
        var out = ""
        for (index, cue) in captions.enumerated() {
            out += "\(index + 1)\n"
            out += "\(formatSRTTimestamp(cue.timeRange.start)) --> \(formatSRTTimestamp(CMTimeAdd(cue.timeRange.start, cue.timeRange.duration)))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    /// Format a `CMTime` as an SRT timestamp `HH:MM:SS,mmm`. Pure — exposed for tests.
    public static func formatSRTTimestamp(_ time: CMTime) -> String {
        let totalMs = Int((CMTimeGetSeconds(time) * 1000.0).rounded())
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let s = totalSec % 60
        let totalMin = totalSec / 60
        let m = totalMin % 60
        let h = totalMin / 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

// MARK: - String helpers

extension String {
    fileprivate func stripUTF8BOM() -> String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }
        return self
    }
}
