import Foundation
import CoreMedia
import Kadr

// MARK: - String parser

extension CaptionParser {

    /// Parse an EBU-TT-D (European Broadcasting Union Timed Text Distribution)
    /// document from a pre-loaded string. v0.6.
    ///
    /// **What this is.** EBU-TT-D (EBU Tech 3380) is the European broadcasters'
    /// distribution-profile subset of W3C TTML. The XML shape mirrors iTT closely
    /// — `<tt>` root, `<body><div><p>` cue tree — but the namespaces
    /// (`urn:ebu:tt:metadata`, `urn:ebu:tt:style`) and time-format constraints
    /// differ. EBU-TT-D mandates the media-clock time form `HH:MM:SS.mmm`;
    /// the frame-count `HH:MM:SS:FF` variant iTT allows is forbidden here.
    ///
    /// **Cue mapping.** Same as ``parseITT(_:)``: each `<p>` inside `<body><div>`
    /// becomes one ``Caption``; `<br/>` between text runs becomes `\n`; inline
    /// styling collapses to plain text. v0.6 ships plain-only — styled EBU-TT-D
    /// (with its complex region-nesting model) is a future-cycle candidate.
    ///
    /// **Tolerance.** The parser doesn't validate the EBU-TT-D namespace
    /// declarations strictly — any TTML-shaped document with `<p>` cues using
    /// `HH:MM:SS.mmm` timing will parse. Adding strict namespace validation
    /// would reject some real-world files that ship with non-canonical
    /// declarations; tolerance is the better default for an ingest library.
    ///
    /// **Errors.** XML structural failures throw
    /// ``CaptionParseError/malformedXML(localizedDescription:)``. Unparseable
    /// time attributes throw ``CaptionParseError/malformedTimestamp(line:raw:)``.
    public static func parseEBUTTD(_ content: String) throws -> [Caption] {
        guard let data = content.data(using: .utf8) else {
            throw CaptionParseError.malformedXML(localizedDescription: "input is not UTF-8 representable")
        }
        let parser = XMLParser(data: data)
        let delegate = EBUTTDParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
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

    /// Parse a single EBU-TT-D time attribute. Returns nil for unparseable
    /// input. EBU-TT-D mandates `HH:MM:SS.mmm` media-clock form — the
    /// frame-count `HH:MM:SS:FF` variant (legal in iTT) is rejected.
    /// Pure — exposed for testing.
    public static func parseEBUTTDTime(_ raw: String) -> CMTime? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // EBU-TT-D is strict: must be HH:MM:SS or HH:MM:SS.mmm. We allow
        // the optional fractional component but reject suffix forms (`1.5s`,
        // `1500ms`) the broader TTML spec permits — the EBU profile forbids
        // them.
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }

        // Seconds may include a fractional component.
        let secondsRaw = String(parts[2])
        let secondsValue: Double
        if let direct = Double(secondsRaw) {
            secondsValue = direct
        } else {
            return nil
        }
        let totalSeconds = Double(hours * 3600 + minutes * 60) + secondsValue
        return CMTime(seconds: totalSeconds, preferredTimescale: 1000)
    }
}

extension Caption {

    /// Load + parse an EBU-TT-D `.xml` / `.ttml` file from disk. Mirrors the
    /// shape of ``load(itt:)``. v0.6.
    public static func load(ebuTTD url: URL) async throws -> [Caption] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CaptionParseError.unreadableFile(url)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw CaptionParseError.unsupportedEncoding(url)
        }
        return try CaptionParser.parseEBUTTD(content)
    }
}

// MARK: - XMLParserDelegate

private final class EBUTTDParserDelegate: NSObject, XMLParserDelegate {

    var captions: [Caption] = []
    var error: Error?

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
        case "p":
            inP = true
            pText = ""
            let beginRaw = attributeDict["begin"] ?? attributeDict["tt:begin"] ?? ""
            let endRaw = attributeDict["end"] ?? attributeDict["tt:end"] ?? ""
            let begin = CaptionParser.parseEBUTTDTime(beginRaw)
            let end = CaptionParser.parseEBUTTDTime(endRaw)
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

    /// Strip namespace prefix (`tt:p` → `p`, `ebuttm:documentMetadata` → ...).
    /// Mirrors the iTT delegate's helper since the XML lineage is shared.
    private func localName(of qualified: String) -> String {
        if let colon = qualified.firstIndex(of: ":") {
            return String(qualified[qualified.index(after: colon)...])
        }
        return qualified
    }
}
