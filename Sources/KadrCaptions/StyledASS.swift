import Foundation
import CoreMedia
import Kadr

// MARK: - Styled ASS / SSA parser (v0.5.0)

extension CaptionParser {

    /// Parse Advanced SubStation Alpha (.ass) content into ``StyledCaption``s,
    /// preserving the cue's most-load-bearing styling: per-cue bold / italic /
    /// underline flags, alignment from `\an<N>` (and legacy `\a<N>`), and
    /// foreground color from `\1c&HBBGGRR&` (alias `\c&HBBGGRR&`).
    ///
    /// Karaoke timing tags (`\k50`), positioning (`\pos(...)`), and font / size
    /// overrides are intentionally dropped — the styled VTT bridge limits its
    /// surface to what `Kadr.TextStyle` can render (`fontName`, `fontSize`,
    /// `color`, `alignment`, `weight`). Per-run inline styling collapses to a
    /// single per-cue flag (mirrors the styled-VTT bridge).
    ///
    /// `\N` / `\n` line breaks become real newlines in the cue's `text`. `\h`
    /// becomes a regular space.
    public static func parseStyledASS(_ content: String) throws -> [StyledCaption] {
        try parseStyledASSorSSA(content)
    }

    /// Parse SubStation Alpha (.ssa) content into ``StyledCaption``s. Same logic
    /// as ``parseStyledASS(_:)`` — both formats share the same override syntax.
    public static func parseStyledSSA(_ content: String) throws -> [StyledCaption] {
        try parseStyledASSorSSA(content)
    }

    private static func parseStyledASSorSSA(_ content: String) throws -> [StyledCaption] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .stripUTF8BOMStyledASS()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var section: String? = nil
        var formatColumns: [String] = []
        var captions: [StyledCaption] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix(";") { continue }
            if trimmed.hasPrefix("!:") { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast())
                formatColumns = []
                continue
            }

            guard section == "Events" else { continue }

            if trimmed.hasPrefix("Format:") {
                let body = String(trimmed.dropFirst("Format:".count))
                formatColumns = body
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                continue
            }

            if trimmed.hasPrefix("Dialogue:") {
                guard !formatColumns.isEmpty else { continue }
                let body = String(trimmed.dropFirst("Dialogue:".count))
                let fields = splitASSDialogue(body, columnCount: formatColumns.count)
                guard fields.count == formatColumns.count else { continue }
                guard let startIdx = formatColumns.firstIndex(of: "Start"),
                      let endIdx = formatColumns.firstIndex(of: "End"),
                      let textIdx = formatColumns.firstIndex(of: "Text") else {
                    continue
                }
                let startRaw = fields[startIdx].trimmingCharacters(in: .whitespaces)
                let endRaw = fields[endIdx].trimmingCharacters(in: .whitespaces)
                guard let start = parseASSTimestamp(startRaw),
                      let end = parseASSTimestamp(endRaw) else {
                    throw CaptionParseError.malformedTimestamp(
                        line: index + 1,
                        raw: "start=\"\(startRaw)\" end=\"\(endRaw)\""
                    )
                }
                let duration = CMTimeSubtract(end, start)
                guard CMTimeCompare(duration, .zero) > 0 else { continue }

                let rawText = fields[textIdx]
                let style = parseASSOverrides(rawText)
                let plain = stripASSOverrides(rawText)

                captions.append(StyledCaption(
                    text: plain,
                    timeRange: CMTimeRange(start: start, duration: duration),
                    alignment: style.alignment,
                    line: style.line,
                    isBold: style.isBold,
                    isItalic: style.isItalic,
                    isUnderlined: style.isUnderlined,
                    color: style.color
                ))
            }
        }

        return captions
    }

    // MARK: - Override parsing

    /// Style flags accumulated from a cue's ASS override blocks. Pure helper —
    /// `internal` rather than `public` because the shape may evolve as more
    /// override codes are surfaced.
    internal struct ASSOverrideStyle {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isUnderlined: Bool = false
        var alignment: StyledCaptionAlignment = .center
        var line: StyledCaptionLine = .auto
        var color: String? = nil
    }

    /// Walk a cue's text and extract the union of style flags from every `{...}`
    /// override block. Last-write-wins for booleans / alignment / color.
    /// Pure — exposed for tests.
    public static func parseASSOverrideFlags(_ text: String) -> (
        isBold: Bool,
        isItalic: Bool,
        isUnderlined: Bool,
        alignment: StyledCaptionAlignment,
        line: StyledCaptionLine,
        color: String?
    ) {
        let style = parseASSOverrides(text)
        return (style.isBold, style.isItalic, style.isUnderlined, style.alignment, style.line, style.color)
    }

    internal static func parseASSOverrides(_ text: String) -> ASSOverrideStyle {
        var style = ASSOverrideStyle()
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] != "{" {
                i = text.index(after: i)
                continue
            }
            // Find the matching close brace.
            guard let close = text[i...].firstIndex(of: "}") else { break }
            let block = String(text[text.index(after: i)..<close])
            applyOverrideBlock(block, to: &style)
            i = text.index(after: close)
        }
        return style
    }

    private static func applyOverrideBlock(_ block: String, to style: inout ASSOverrideStyle) {
        // ASS chains override codes with `\` inside a single `{...}`. Split on
        // backslash, ignore the leading empty piece.
        let codes = block.split(separator: "\\", omittingEmptySubsequences: true)
        for code in codes {
            applyOverrideCode(String(code), to: &style)
        }
    }

    private static func applyOverrideCode(_ code: String, to style: inout ASSOverrideStyle) {
        // Bold: `b1` / `b0` (or `b<weight>` for variable weights).
        if code.hasPrefix("b"), let value = Int(code.dropFirst()) {
            style.isBold = value != 0
            return
        }
        if code.hasPrefix("i"), let value = Int(code.dropFirst()) {
            style.isItalic = value != 0
            return
        }
        if code.hasPrefix("u"), let value = Int(code.dropFirst()) {
            style.isUnderlined = value != 0
            return
        }
        // Alignment codes — `\an<N>` (modern numpad layout) takes precedence over
        // legacy `\a<N>` (different mapping).
        if code.hasPrefix("an"), let value = Int(code.dropFirst(2)) {
            (style.alignment, style.line) = mapANAlignment(value)
            return
        }
        if code.hasPrefix("a"), code.count > 1, let value = Int(code.dropFirst()) {
            (style.alignment, style.line) = mapLegacyAAlignment(value)
            return
        }
        // Primary color: `\1c&HBBGGRR&` or alias `\c&HBBGGRR&`. (`&Hxxxxxx&` is
        // BGR hex; we re-pack into RGB for portability.)
        if code.hasPrefix("1c") || code.hasPrefix("c") {
            let payload = code.hasPrefix("1c") ? String(code.dropFirst(2)) : String(code.dropFirst())
            if let hex = parseASSColorPayload(payload) {
                style.color = hex
            }
            return
        }
    }

    /// Map the modern `\an<N>` numpad alignment code (1–9) onto the
    /// `(alignment, line)` pair the bridge consumes. Pure — exposed for tests.
    public static func mapANAlignment(_ code: Int) -> (StyledCaptionAlignment, StyledCaptionLine) {
        switch code {
        case 1: return (.start,  .bottom)
        case 2: return (.center, .bottom)
        case 3: return (.end,    .bottom)
        case 4: return (.start,  .percent(50))
        case 5: return (.center, .percent(50))
        case 6: return (.end,    .percent(50))
        case 7: return (.start,  .top)
        case 8: return (.center, .top)
        case 9: return (.end,    .top)
        default: return (.center, .auto)
        }
    }

    /// Map the legacy `\a<N>` alignment code (SSA style) onto the
    /// `(alignment, line)` pair. Bit mask: 1=left, 2=center, 3=right; `+4` =
    /// top, `+8` = middle. Pure — exposed for tests.
    public static func mapLegacyAAlignment(_ code: Int) -> (StyledCaptionAlignment, StyledCaptionLine) {
        let horizontal: StyledCaptionAlignment
        switch code & 0x3 {
        case 1: horizontal = .start
        case 3: horizontal = .end
        default: horizontal = .center
        }
        let line: StyledCaptionLine
        if code & 0x4 != 0 {
            line = .top
        } else if code & 0x8 != 0 {
            line = .percent(50)
        } else {
            line = .bottom
        }
        return (horizontal, line)
    }

    /// Parse an ASS color payload. Accepts `&HBBGGRR&` and `&HAABBGGRR&` (with
    /// optional trailing `&`). Returns a `#RRGGBB` (or `#RRGGBBAA`) hex string
    /// matching the ``StyledCaption/color`` contract. Pure — exposed for tests.
    public static func parseASSColorPayload(_ payload: String) -> String? {
        var s = payload.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("&") { s.removeLast() }
        if s.hasPrefix("&") { s.removeFirst() }
        if s.hasPrefix("H") || s.hasPrefix("h") { s.removeFirst() }
        guard !s.isEmpty else { return nil }
        // Pad out to even length — ASS sometimes drops leading zeros.
        if s.count % 2 == 1 { s = "0" + s }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let bb, gg, rr: UInt64
        let aa: UInt64?
        if s.count <= 6 {
            bb = (value >> 16) & 0xFF
            gg = (value >>  8) & 0xFF
            rr = value & 0xFF
            aa = nil
        } else {
            // ASS alpha is inverted: 0 = opaque, 255 = transparent. Flip on import.
            let assAlpha = (value >> 24) & 0xFF
            aa = 0xFF - assAlpha
            bb = (value >> 16) & 0xFF
            gg = (value >>  8) & 0xFF
            rr = value & 0xFF
        }
        if let aa {
            return String(format: "#%02X%02X%02X%02X", rr, gg, bb, aa)
        }
        return String(format: "#%02X%02X%02X", rr, gg, bb)
    }
}

// MARK: - File loaders

extension Caption {

    /// Load and parse a styled ASS file into ``StyledCaption``s. Encoding falls
    /// back to Windows-1252 when UTF-8 decoding fails.
    public static func loadStyled(ass url: URL) async throws -> [StyledCaption] {
        try await loadStyledASSorSSA(url: url, parser: CaptionParser.parseStyledASS)
    }

    /// Load and parse a styled SSA file into ``StyledCaption``s. Same encoding
    /// logic as ``loadStyled(ass:)``.
    public static func loadStyled(ssa url: URL) async throws -> [StyledCaption] {
        try await loadStyledASSorSSA(url: url, parser: CaptionParser.parseStyledSSA)
    }

    private static func loadStyledASSorSSA(
        url: URL,
        parser: @Sendable (String) throws -> [StyledCaption]
    ) async throws -> [StyledCaption] {
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
        return try parser(content)
    }
}

// MARK: - String helpers

extension String {
    fileprivate func stripUTF8BOMStyledASS() -> String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }
        return self
    }
}
