import Foundation
import CoreMedia
import Kadr

// MARK: - String parser

extension CaptionParser {

    /// Parse iTunes Timed Text (.itt) content from a pre-loaded string.
    ///
    /// **Cue mapping.** Each `<p>` element inside `<body><div>` becomes one ``Caption``.
    /// `<br/>` between text runs becomes `\n`. Inline `<span>` styling is flattened to
    /// plain text (same v0.3 styled-bridge promise as VTT). Multiple `<div>` blocks
    /// concatenate.
    ///
    /// **Time attributes.** Reads `begin` / `end` (with or without `tt:` prefix). Forms
    /// supported: `HH:MM:SS.mmm`, `HH:MM:SS:FF` (frame count, approximated at the
    /// document's declared `frameRate` or 30 fps fallback), `1.5s`, `1500ms`, plain
    /// `1.5` (seconds).
    ///
    /// **Errors.** XML structural failures throw
    /// ``CaptionParseError/malformedXML(localizedDescription:)``. Unparseable time
    /// attributes throw ``CaptionParseError/malformedTimestamp(line:raw:)``.
    public static func parseITT(_ content: String) throws -> [Caption] {
        guard let data = content.data(using: .utf8) else {
            throw CaptionParseError.malformedXML(localizedDescription: "input is not UTF-8 representable")
        }
        let parser = XMLParser(data: data)
        let delegate = ITTParserDelegate()
        parser.delegate = delegate
        let ok = parser.parse()
        if let recorded = delegate.error {
            throw recorded
        }
        if !ok {
            let desc = parser.parserError?.localizedDescription
                ?? "XML parsing failed at line \(parser.lineNumber)"
            throw CaptionParseError.malformedXML(localizedDescription: desc)
        }
        return delegate.captions
    }

    /// Parse a single iTT time attribute. Returns `nil` for unparseable input. Pure —
    /// exposed for testing. `frameRate` controls how `HH:MM:SS:FF` (frame-count form)
    /// is approximated; default 30.
    public static func parseITTTime(_ raw: String, frameRate: Double = 30.0) -> CMTime? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Suffix forms: 1500ms / 1.5s
        if trimmed.hasSuffix("ms") {
            let body = trimmed.dropLast(2)
            guard let ms = Double(body) else { return nil }
            return CMTime(seconds: ms / 1000.0, preferredTimescale: 1000)
        }
        if trimmed.hasSuffix("s"), !trimmed.hasSuffix("ms") {
            let body = trimmed.dropLast()
            guard let s = Double(body) else { return nil }
            return CMTime(seconds: s, preferredTimescale: 1000)
        }
        // Plain seconds (no suffix, no colon)
        if !trimmed.contains(":") {
            guard let s = Double(trimmed) else { return nil }
            return CMTime(seconds: s, preferredTimescale: 1000)
        }
        // Colon-separated forms: HH:MM:SS.mmm or HH:MM:SS:FF
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 || parts.count == 4 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        if parts.count == 4 {
            // HH:MM:SS:FF — approximate at frameRate.
            guard let s = Int(parts[2]), let f = Int(parts[3]), frameRate > 0 else { return nil }
            let total = Double(h * 3600 + m * 60 + s) + Double(f) / frameRate
            return CMTime(seconds: total, preferredTimescale: 1000)
        }
        // HH:MM:SS.mmm
        let secComps = parts[2].split(separator: ".")
        guard let s = Int(secComps[0]) else { return nil }
        var ms = 0
        if secComps.count == 2 {
            var msStr = String(secComps[1])
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

    /// Load and parse an iTT (.itt) file from disk. UTF-8 only — TTML / iTT files in
    /// the wild are universally UTF-8 (the spec requires it), so unlike SRT we don't
    /// fall back to Windows-1252.
    public static func load(itt url: URL) async throws -> [Caption] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CaptionParseError.unreadableFile(url)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw CaptionParseError.unsupportedEncoding(url)
        }
        return try CaptionParser.parseITT(content)
    }
}

// MARK: - XMLParserDelegate

private final class ITTParserDelegate: NSObject, XMLParserDelegate {

    var captions: [Caption] = []
    var error: Error?

    private var frameRate: Double = 30.0
    private var inP: Bool = false
    private var pBegin: CMTime?
    private var pEnd: CMTime?
    private var pText: String = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let local = localName(of: elementName)
        switch local {
        case "tt":
            // Read frame rate from any of the common attribute forms.
            if let raw = attributeDict["ttp:frameRate"]
                ?? attributeDict["frameRate"]
                ?? attributeDict["tt:frameRate"],
               let val = Double(raw), val > 0 {
                frameRate = val
            }
        case "p":
            inP = true
            pText = ""
            let beginRaw = attributeDict["begin"] ?? attributeDict["tt:begin"] ?? ""
            let endRaw = attributeDict["end"] ?? attributeDict["tt:end"] ?? ""
            let begin = CaptionParser.parseITTTime(beginRaw, frameRate: frameRate)
            let end = CaptionParser.parseITTTime(endRaw, frameRate: frameRate)
            if begin == nil || end == nil {
                error = CaptionParseError.malformedTimestamp(
                    line: parser.lineNumber,
                    raw: "begin=\"\(beginRaw)\" end=\"\(endRaw)\""
                )
                parser.abortParsing()
                return
            }
            pBegin = begin
            pEnd = end
        case "br":
            if inP { pText += "\n" }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if localName(of: elementName) == "p", inP {
            inP = false
            if let begin = pBegin, let end = pEnd {
                let duration = CMTimeSubtract(end, begin)
                if CMTimeCompare(duration, .zero) > 0 {
                    let text = pText.trimmingCharacters(in: .whitespacesAndNewlines)
                    captions.append(Caption(
                        text: text,
                        timeRange: CMTimeRange(start: begin, duration: duration)
                    ))
                }
            }
            pBegin = nil
            pEnd = nil
            pText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inP { pText += string }
    }

    /// Strip namespace prefix (`tt:p` → `p`). XMLParser usually delivers the local
    /// name already, but defending here keeps the delegate robust to both delivery
    /// modes.
    private func localName(of qualified: String) -> String {
        if let colon = qualified.firstIndex(of: ":") {
            return String(qualified[qualified.index(after: colon)...])
        }
        return qualified
    }
}
