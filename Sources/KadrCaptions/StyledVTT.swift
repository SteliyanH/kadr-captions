import Foundation
import CoreMedia
import Kadr

// MARK: - Pure helpers

extension CaptionParser {

    /// Parse a VTT timestamp line of the form
    /// `HH:MM:SS.mmm --> HH:MM:SS.mmm align:start position:25%`, returning the
    /// time range plus the trailing settings string (everything after the second
    /// timestamp). Returns `nil` for unparseable input. Pure — exposed for tests.
    public static func parseStyledVTTTimestampLine(_ raw: String) -> (CMTimeRange, String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        let rhsRaw = parts[1].trimmingCharacters(in: .whitespaces)
        let rhs: String
        let settings: String
        if let space = rhsRaw.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            rhs = String(rhsRaw[..<space])
            settings = String(rhsRaw[rhsRaw.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        } else {
            rhs = rhsRaw
            settings = ""
        }
        guard let start = parseVTTTimestamp(lhs), let end = parseVTTTimestamp(rhs) else {
            return nil
        }
        let duration = CMTimeSubtract(end, start)
        guard CMTimeCompare(duration, .zero) > 0 else { return nil }
        return (CMTimeRange(start: start, duration: duration), settings)
    }

    /// Parse a VTT cue settings string (`align:start position:25% line:20%`) into a
    /// tuple of alignment / line / position. Unrecognized settings are ignored.
    /// Pure — exposed for tests.
    public static func parseVTTCueSettings(
        _ raw: String
    ) -> (alignment: StyledCaptionAlignment, line: StyledCaptionLine, position: Double) {
        var alignment: StyledCaptionAlignment = .center
        var line: StyledCaptionLine = .auto
        var position: Double = 0.5

        let tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
        for token in tokens {
            guard let colon = token.firstIndex(of: ":") else { continue }
            let key = String(token[..<colon])
            let value = String(token[token.index(after: colon)...])
            switch key {
            case "align":
                switch value {
                case "start", "left":  alignment = .start
                case "center", "middle": alignment = .center
                case "end", "right":   alignment = .end
                default: break
                }
            case "line":
                line = parseVTTLine(value)
            case "position":
                if let p = parsePercent(value) {
                    position = p
                }
            default:
                break
            }
        }
        return (alignment, line, position)
    }

    /// Parse a `line:` setting value: `auto`, `0%` (top), `100%` (bottom), `NN%`
    /// (percent), or a plain integer (line count — treated as auto in v0.3 since
    /// kadr can't compute line height without a renderer pass).
    static func parseVTTLine(_ value: String) -> StyledCaptionLine {
        if value == "auto" { return .auto }
        if let percent = parsePercent(value) {
            let pct = percent * 100  // back to 0...100 for the enum payload
            if abs(pct) < 0.001 { return .top }
            if abs(pct - 100) < 0.001 { return .bottom }
            return .percent(pct)
        }
        // Plain integer line counts (e.g. "line:-1") are not surfaced in v0.3.
        return .auto
    }

    /// Parse a `25%` / `0.25` / `25` style value into `0...1`. Returns `nil` for
    /// unparseable input. Percent values outside `0...100` are clamped at the edges.
    static func parsePercent(_ raw: String) -> Double? {
        if raw.hasSuffix("%") {
            let body = raw.dropLast()
            guard let v = Double(body) else { return nil }
            return max(0, min(1, v / 100.0))
        }
        guard let v = Double(raw) else { return nil }
        // Bare numbers are ambiguous; treat <= 1 as already-normalized, > 1 as
        // percent.
        if v > 1 {
            return max(0, min(1, v / 100.0))
        }
        return max(0, min(1, v))
    }

    /// Strip inline tags from a VTT cue text, recording the styling flags / classes /
    /// speaker. Pure — exposed for tests.
    ///
    /// Returns `(plainText, isBold, isItalic, isUnderlined, speaker, classes)`. The
    /// caller assembles these into a `StyledCaption`. v0.3 records "any tag of this
    /// kind appeared in the cue" rather than per-run state.
    public static func extractStyledRuns(
        _ line: String
    ) -> (
        text: String,
        isBold: Bool,
        isItalic: Bool,
        isUnderlined: Bool,
        speaker: String?,
        classes: [String]
    ) {
        var plain = ""
        var isBold = false
        var isItalic = false
        var isUnderlined = false
        var speaker: String? = nil
        var classes: [String] = []

        var insideTag = false
        var tagBody = ""

        for ch in line {
            if ch == "<" {
                insideTag = true
                tagBody = ""
                continue
            }
            if ch == ">" {
                if insideTag {
                    processTagBody(
                        tagBody,
                        isBold: &isBold,
                        isItalic: &isItalic,
                        isUnderlined: &isUnderlined,
                        speaker: &speaker,
                        classes: &classes
                    )
                }
                insideTag = false
                tagBody = ""
                continue
            }
            if insideTag {
                tagBody.append(ch)
            } else {
                plain.append(ch)
            }
        }

        return (plain, isBold, isItalic, isUnderlined, speaker, classes)
    }

    /// Apply a single tag body (the text between `<` and `>`) to the running flags.
    /// Pure helper — separate so the per-character scanner stays readable.
    private static func processTagBody(
        _ body: String,
        isBold: inout Bool,
        isItalic: inout Bool,
        isUnderlined: inout Bool,
        speaker: inout String?,
        classes: inout [String]
    ) {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return }
        // Closing tag — leading slash. Ignored for flag-flipping purposes (we only
        // care that the flag was set at some point in the cue).
        if trimmed.hasPrefix("/") { return }

        // Timed-text marker: <00:00:01.500>. First char digit → ignore.
        if let first = trimmed.first, first.isNumber { return }

        // Tag name + optional modifiers. Tag bodies look like:
        //   i
        //   b
        //   u
        //   c.classname.other
        //   v Speaker
        //   c
        //
        // Split on whitespace first to peel off `v Speaker`.
        let nameAndExtras = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let nameRaw = nameAndExtras.first else { return }
        let name = String(nameRaw)

        // Class-suffix form: c.foo.bar
        if name.hasPrefix("c.") || name == "c" {
            let parts = name.split(separator: ".", omittingEmptySubsequences: true)
            for part in parts.dropFirst() {
                classes.append(String(part))
            }
            return
        }

        switch name {
        case "i": isItalic = true
        case "b": isBold = true
        case "u": isUnderlined = true
        case "v":
            if nameAndExtras.count >= 2 {
                speaker = nameAndExtras.dropFirst().joined(separator: " ")
            }
        default:
            break
        }
    }
}

// MARK: - Styled VTT parser

extension CaptionParser {

    /// Parse WebVTT (.vtt) content into ``StyledCaption`` values, preserving cue
    /// settings (`align:`, `line:`, `position:`) and inline styling (`<i>`, `<b>`,
    /// `<u>`, `<c.classname>`, `<v Speaker>`) as flags / classes / speaker on the
    /// resulting cues.
    ///
    /// Same WEBVTT header / NOTE / REGION / STYLE / cue-identifier handling as
    /// ``parseVTT(_:)``. The plain-text component of each cue (with all tags
    /// stripped) matches what ``parseVTT(_:)`` would produce for the same input.
    public static func parseStyledVTT(_ content: String) throws -> [StyledCaption] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .stripUTF8BOMStyledVTT()

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw CaptionParseError.missingHeader
        }
        let header = firstNonEmpty.trimmingCharacters(in: .whitespaces)
        let isHeader = header == "WEBVTT"
            || header.hasPrefix("WEBVTT ")
            || header.hasPrefix("WEBVTT\t")
        guard isHeader else { throw CaptionParseError.missingHeader }

        var captions: [StyledCaption] = []
        var i = (lines.firstIndex(of: firstNonEmpty) ?? 0) + 1

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            if isVTTSkipBlockHeader(trimmed) {
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    i += 1
                }
                continue
            }

            let timestampLineIndex: Int
            if line.contains("-->") {
                timestampLineIndex = i
            } else {
                timestampLineIndex = i + 1
                if timestampLineIndex >= lines.count { break }
            }

            let tsRaw = lines[timestampLineIndex]
            guard let (range, settingsRaw) = parseStyledVTTTimestampLine(tsRaw) else {
                throw CaptionParseError.malformedTimestamp(line: timestampLineIndex + 1, raw: tsRaw)
            }
            let (alignment, lineSetting, position) = parseVTTCueSettings(settingsRaw)

            // Collect text lines until blank/EOF, accumulating styling across all of them.
            var plainLines: [String] = []
            var anyBold = false
            var anyItalic = false
            var anyUnderlined = false
            var firstSpeaker: String? = nil
            var allClasses: [String] = []
            var j = timestampLineIndex + 1
            while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                let extracted = extractStyledRuns(lines[j])
                plainLines.append(extracted.text)
                if extracted.isBold { anyBold = true }
                if extracted.isItalic { anyItalic = true }
                if extracted.isUnderlined { anyUnderlined = true }
                if firstSpeaker == nil, let s = extracted.speaker { firstSpeaker = s }
                allClasses.append(contentsOf: extracted.classes)
                j += 1
            }
            let text = plainLines.joined(separator: "\n")

            captions.append(StyledCaption(
                text: text,
                timeRange: range,
                alignment: alignment,
                line: lineSetting,
                position: position,
                isBold: anyBold,
                isItalic: anyItalic,
                isUnderlined: anyUnderlined,
                speaker: firstSpeaker,
                classes: allClasses
            ))
            i = j + 1
        }

        return captions
    }
}

// MARK: - File loader

extension Caption {

    /// Load and parse a WebVTT file as ``StyledCaption`` values, preserving cue
    /// settings and inline styling. UTF-8 default with Windows-1252 fallback.
    public static func loadStyled(vtt url: URL) async throws -> [StyledCaption] {
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
        return try CaptionParser.parseStyledVTT(content)
    }
}

// MARK: - String helpers

extension String {
    fileprivate func stripUTF8BOMStyledVTT() -> String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }
        return self
    }
}
