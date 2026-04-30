import Foundation
import CoreMedia
import Kadr

// MARK: - String parser

extension CaptionParser {

    /// Parse WebVTT (.vtt) content from a pre-loaded string.
    ///
    /// **Header.** The file must start with `WEBVTT` (optionally followed by space/tab
    /// and any text on the same line — the `WEBVTT - some description` form). Throws
    /// ``CaptionParseError/missingHeader`` if absent.
    ///
    /// **Block types.** `NOTE` blocks (comments), `REGION` blocks (positioning), and
    /// `STYLE` blocks (CSS) are tolerated and skipped — the parser surfaces only cue
    /// blocks. Cue identifiers (an arbitrary string line before the timestamp line) are
    /// ignored.
    ///
    /// **Cue settings.** Anything on the timestamp line after the second timestamp
    /// (`align:start`, `position:50%`, `line:20%`, `region:my-region`, etc.) is stripped.
    /// Re-enabling cue settings is planned for v0.3+ when the styled-caption builder
    /// lands.
    ///
    /// **Inline styles.** `<c.classname>...</c>`, `<i>`, `<b>`, `<u>`, `<v Speaker>`,
    /// `<00:00:01.500>` (timed text), and any other angle-bracket tags are stripped to
    /// plain text in v0.1. Same v0.3+ note applies.
    ///
    /// **Line endings / BOM.** CRLF / LF / mixed are tolerated; UTF-8 BOM is stripped.
    public static func parseVTT(_ content: String) throws -> [Caption] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .stripUTF8BOMVTT()

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Header check — first non-empty line must be "WEBVTT" (with optional trailing
        // text after a space or tab).
        guard let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw CaptionParseError.missingHeader
        }
        let header = firstNonEmpty.trimmingCharacters(in: .whitespaces)
        let isHeader = header == "WEBVTT"
            || header.hasPrefix("WEBVTT ")
            || header.hasPrefix("WEBVTT\t")
        guard isHeader else {
            throw CaptionParseError.missingHeader
        }

        var captions: [Caption] = []
        var i = (lines.firstIndex(of: firstNonEmpty) ?? 0) + 1

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines.
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Skip NOTE / REGION / STYLE blocks — read until next blank line.
            if isVTTSkipBlockHeader(trimmed) {
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    i += 1
                }
                continue
            }

            // Locate the timestamp line. If the current line doesn't contain "-->",
            // it's a cue identifier — skip it.
            let timestampLineIndex: Int
            if line.contains("-->") {
                timestampLineIndex = i
            } else {
                timestampLineIndex = i + 1
                if timestampLineIndex >= lines.count {
                    break
                }
            }

            let tsRaw = lines[timestampLineIndex]
            guard let range = parseVTTTimestampLine(tsRaw) else {
                throw CaptionParseError.malformedTimestamp(line: timestampLineIndex + 1, raw: tsRaw)
            }

            // Collect text lines until a blank line or EOF, stripping inline tags.
            var textLines: [String] = []
            var j = timestampLineIndex + 1
            while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(stripVTTInlineTags(lines[j]))
                j += 1
            }
            let text = textLines.joined(separator: "\n")
            captions.append(Caption(text: text, timeRange: range))
            i = j + 1
        }

        return captions
    }

    /// Parse a VTT timestamp line `HH:MM:SS.mmm --> HH:MM:SS.mmm` (with optional cue
    /// settings after the second timestamp). Returns `nil` for unparseable input.
    /// `MM:SS.mmm` (no hour component) is also accepted per the WebVTT spec.
    public static func parseVTTTimestampLine(_ raw: String) -> CMTimeRange? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        // Strip cue settings — anything after the first whitespace following the second timestamp.
        let rhsRaw = parts[1].trimmingCharacters(in: .whitespaces)
        let rhs: String
        if let space = rhsRaw.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            rhs = String(rhsRaw[..<space])
        } else {
            rhs = rhsRaw
        }
        guard let start = parseVTTTimestamp(lhs), let end = parseVTTTimestamp(rhs) else {
            return nil
        }
        let duration = CMTimeSubtract(end, start)
        guard CMTimeCompare(duration, .zero) > 0 else { return nil }
        return CMTimeRange(start: start, duration: duration)
    }

    /// Parse a single VTT timestamp. `HH:MM:SS.mmm` and `MM:SS.mmm` are both accepted.
    /// Comma-separated milliseconds (SRT style) are also tolerated.
    public static func parseVTTTimestamp(_ raw: String) -> CMTime? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        let h: Int
        let m: Int
        let secPart: Substring
        switch parts.count {
        case 3:
            guard let parsedH = Int(parts[0]), let parsedM = Int(parts[1]) else { return nil }
            h = parsedH; m = parsedM; secPart = parts[2]
        case 2:
            guard let parsedM = Int(parts[0]) else { return nil }
            h = 0; m = parsedM; secPart = parts[1]
        default:
            return nil
        }
        let secComponents = secPart.split(separator: ".")
        guard let s = Int(secComponents[0]) else { return nil }
        var ms = 0
        if secComponents.count == 2 {
            var msStr = String(secComponents[1])
            while msStr.count < 3 { msStr += "0" }
            if msStr.count > 3 { msStr = String(msStr.prefix(3)) }
            guard let parsed = Int(msStr) else { return nil }
            ms = parsed
        }
        let total = Double(h * 3600 + m * 60 + s) + Double(ms) / 1000.0
        return CMTime(seconds: total, preferredTimescale: 1000)
    }

    /// Pure helper: returns `true` if `trimmedLine` is the start of a `NOTE`, `REGION`,
    /// or `STYLE` block per the WebVTT grammar. The block continues until the next
    /// blank line.
    static func isVTTSkipBlockHeader(_ trimmedLine: String) -> Bool {
        if trimmedLine == "NOTE" || trimmedLine.hasPrefix("NOTE ") || trimmedLine.hasPrefix("NOTE\t") { return true }
        if trimmedLine == "REGION" { return true }
        if trimmedLine == "STYLE" { return true }
        return false
    }

    /// Pure helper: strip `<...>` tags from a single VTT cue text line. Removes inline
    /// styles, voice tags, class tags, and timed-text markers. Pure so the regex-free
    /// implementation stays unit-testable. Whitespace between consecutive stripped tags
    /// is preserved.
    public static func stripVTTInlineTags(_ line: String) -> String {
        var out = ""
        var depth = 0
        for ch in line {
            if ch == "<" {
                depth += 1
                continue
            }
            if ch == ">" {
                if depth > 0 { depth -= 1 }
                continue
            }
            if depth == 0 {
                out.append(ch)
            }
        }
        return out
    }
}

// MARK: - File loader

extension Caption {

    /// Load and parse a WebVTT (.vtt) file from disk. UTF-8 default; falls back to
    /// Windows-1252 for non-UTF-8 files (rare in the wild for WebVTT, but the same
    /// fallback applies as SRT for consistency). Throws ``CaptionParseError`` for I/O,
    /// encoding, header, or content errors.
    public static func load(vtt url: URL) async throws -> [Caption] {
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
        return try CaptionParser.parseVTT(content)
    }
}

// MARK: - Writer

extension CaptionAuthor {

    /// Write captions to disk as WebVTT. UTF-8 encoded, LF line endings, mandatory
    /// `WEBVTT` header. Existing file at `url` is overwritten.
    public static func writeVTT(_ captions: [Caption], to url: URL) async throws {
        let content = renderVTT(captions)
        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            throw CaptionParseError.unreadableFile(url)
        }
    }

    /// Render a WebVTT body for a list of captions. Pure — exposed for tests and for
    /// callers wanting the string form. Header is `WEBVTT\n\n`; cue indices are not
    /// emitted (optional in WebVTT).
    public static func renderVTT(_ captions: [Caption]) -> String {
        var out = "WEBVTT\n\n"
        for cue in captions {
            out += "\(formatVTTTimestamp(cue.timeRange.start)) --> \(formatVTTTimestamp(CMTimeAdd(cue.timeRange.start, cue.timeRange.duration)))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    /// Format a `CMTime` as a VTT timestamp `HH:MM:SS.mmm`. Pure — exposed for tests.
    public static func formatVTTTimestamp(_ time: CMTime) -> String {
        let totalMs = Int((CMTimeGetSeconds(time) * 1000.0).rounded())
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let s = totalSec % 60
        let totalMin = totalSec / 60
        let m = totalMin % 60
        let h = totalMin / 60
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}

// MARK: - String helpers

extension String {
    fileprivate func stripUTF8BOMVTT() -> String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }
        return self
    }
}
