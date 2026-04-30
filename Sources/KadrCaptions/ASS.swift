import Foundation
import CoreMedia
import Kadr

// MARK: - String parser

extension CaptionParser {

    /// Parse Advanced SubStation Alpha (.ass) content from a pre-loaded string.
    /// Reads the `[Events]` section's `Format:` line for column ordering and emits
    /// one ``Caption`` per `Dialogue:` row. Style override blocks (`{\b1}`,
    /// `{\c&HFFFFFF&}`, etc.) and karaoke timing tags (`{\k50}`) are stripped.
    /// `\N` / `\n` line breaks become `\n`.
    public static func parseASS(_ content: String) throws -> [Caption] {
        try parseASSorSSA(content)
    }

    /// Parse SubStation Alpha (.ssa) content from a pre-loaded string. Same logic
    /// as ``parseASS(_:)`` — the formats differ in their style-block schema, which
    /// v0.4 doesn't surface.
    public static func parseSSA(_ content: String) throws -> [Caption] {
        try parseASSorSSA(content)
    }

    private static func parseASSorSSA(_ content: String) throws -> [Caption] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .stripUTF8BOMASS()
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var section: String? = nil
        var formatColumns: [String] = []
        var captions: [Caption] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip blanks and ASS-style comment lines (`;` for SSA, `!:` for ASS).
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
                let text = stripASSOverrides(fields[textIdx])
                captions.append(Caption(
                    text: text,
                    timeRange: CMTimeRange(start: start, duration: duration)
                ))
            }
            // `Comment:` and other event types are silently skipped.
        }

        return captions
    }

    // MARK: - Pure helpers

    /// Parse an ASS / SSA timestamp `H:MM:SS.cc` (centisecond precision; hour digit
    /// not zero-padded). Returns `nil` for unparseable input. Pure — exposed for
    /// testing.
    public static func parseASSTimestamp(_ raw: String) -> CMTime? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let secComps = parts[2].split(separator: ".")
        guard let s = Int(secComps[0]) else { return nil }
        var cs = 0
        if secComps.count == 2 {
            var csStr = String(secComps[1])
            // ASS centiseconds are 2 digits. Pad / truncate.
            while csStr.count < 2 { csStr += "0" }
            if csStr.count > 2 { csStr = String(csStr.prefix(2)) }
            guard let parsed = Int(csStr) else { return nil }
            cs = parsed
        }
        let total = Double(h * 3600 + m * 60 + s) + Double(cs) / 100.0
        return CMTime(seconds: total, preferredTimescale: 1000)
    }

    /// Split a Dialogue body into `columnCount` fields. Splits on the first
    /// `columnCount - 1` commas; the trailing field captures the remainder so
    /// commas inside the cue text aren't mistaken for separators. Pure.
    public static func splitASSDialogue(_ body: String, columnCount: Int) -> [String] {
        guard columnCount > 0 else { return [] }
        var fields: [String] = []
        var current = body
        for _ in 0..<(columnCount - 1) {
            guard let comma = current.firstIndex(of: ",") else {
                return fields  // malformed — fewer commas than expected
            }
            fields.append(String(current[..<comma]))
            current = String(current[current.index(after: comma)...])
        }
        fields.append(current)
        return fields
    }

    /// Strip ASS / SSA override blocks (`{\b1}`, `{\c&HFFFFFF&}`, `{\k50}`, etc.)
    /// from a cue text and convert `\N` / `\n` to real newlines. `\h` (hard space)
    /// becomes a regular space. Pure — exposed for testing.
    public static func stripASSOverrides(_ text: String) -> String {
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "{" {
                // Skip everything through the closing brace.
                while i < text.endIndex, text[i] != "}" {
                    i = text.index(after: i)
                }
                if i < text.endIndex {
                    i = text.index(after: i)  // consume `}`
                }
                continue
            }
            if ch == "\\", text.index(after: i) < text.endIndex {
                let next = text[text.index(after: i)]
                if next == "N" || next == "n" {
                    out.append("\n")
                    i = text.index(i, offsetBy: 2)
                    continue
                }
                if next == "h" {
                    out.append(" ")
                    i = text.index(i, offsetBy: 2)
                    continue
                }
            }
            out.append(ch)
            i = text.index(after: i)
        }
        return out
    }
}

// MARK: - File loaders

extension Caption {

    /// Load and parse an Advanced SubStation Alpha (.ass) file. UTF-8 default with
    /// Windows-1252 fallback for legacy files.
    public static func load(ass url: URL) async throws -> [Caption] {
        try await loadASSorSSA(url: url, parser: CaptionParser.parseASS)
    }

    /// Load and parse a SubStation Alpha (.ssa) file. UTF-8 default with
    /// Windows-1252 fallback.
    public static func load(ssa url: URL) async throws -> [Caption] {
        try await loadASSorSSA(url: url, parser: CaptionParser.parseSSA)
    }

    private static func loadASSorSSA(
        url: URL,
        parser: @Sendable (String) throws -> [Caption]
    ) async throws -> [Caption] {
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
    fileprivate func stripUTF8BOMASS() -> String {
        if hasPrefix("\u{FEFF}") {
            return String(dropFirst())
        }
        return self
    }
}
