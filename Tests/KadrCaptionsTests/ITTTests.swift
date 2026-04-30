import Testing
import CoreMedia
import Foundation
@testable import KadrCaptions

/// Tests for v0.2 Tier 1 — iTT parser, time-attribute helpers, and auto-detect
/// dispatch update.
struct ITTTests {

    // MARK: - parseITTTime

    @Test func parsesClockTime() {
        let t = CaptionParser.parseITTTime("00:01:23.456")
        #expect(abs(CMTimeGetSeconds(t!) - 83.456) < 0.0001)
    }

    @Test func parsesClockTimeWithoutMilliseconds() {
        let t = CaptionParser.parseITTTime("00:01:23")
        #expect(abs(CMTimeGetSeconds(t!) - 83.0) < 0.0001)
    }

    @Test func parsesFrameCountAt30fps() {
        // 00:00:01:15 at 30 fps = 1.5 seconds
        let t = CaptionParser.parseITTTime("00:00:01:15", frameRate: 30)
        #expect(abs(CMTimeGetSeconds(t!) - 1.5) < 0.0001)
    }

    @Test func parsesFrameCountAt2997fps() {
        // 00:00:01:15 at 29.97 fps ≈ 1.5005 seconds. CMTime at timescale 1000 has
        // ~1ms quantization; loosen the tolerance to match.
        let t = CaptionParser.parseITTTime("00:00:01:15", frameRate: 29.97)
        #expect(abs(CMTimeGetSeconds(t!) - (1.0 + 15.0 / 29.97)) < 0.002)
    }

    @Test func parsesSecondsSuffix() {
        let t = CaptionParser.parseITTTime("1.5s")
        #expect(abs(CMTimeGetSeconds(t!) - 1.5) < 0.0001)
    }

    @Test func parsesMillisecondsSuffix() {
        let t = CaptionParser.parseITTTime("1500ms")
        #expect(abs(CMTimeGetSeconds(t!) - 1.5) < 0.0001)
    }

    @Test func parsesPlainSecondsAsDouble() {
        let t = CaptionParser.parseITTTime("2.75")
        #expect(abs(CMTimeGetSeconds(t!) - 2.75) < 0.0001)
    }

    @Test func rejectsEmptyAndGarbage() {
        #expect(CaptionParser.parseITTTime("") == nil)
        #expect(CaptionParser.parseITTTime("garbage") == nil)
        #expect(CaptionParser.parseITTTime("aa:bb:cc") == nil)
    }

    @Test func rejectsZeroFrameRate() {
        #expect(CaptionParser.parseITTTime("00:00:01:15", frameRate: 0) == nil)
    }

    // MARK: - parseITT — happy paths

    private let minimalDoc = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tt xmlns="http://www.w3.org/ns/ttml">
      <body>
        <div>
          <p begin="00:00:00.000" end="00:00:02.000">Hello</p>
          <p begin="00:00:02.000" end="00:00:05.000">World</p>
        </div>
      </body>
    </tt>
    """

    @Test func parsesMinimalDoc() {
        let cues = try! CaptionParser.parseITT(minimalDoc)
        #expect(cues.count == 2)
        #expect(cues.map(\.text) == ["Hello", "World"])
        #expect(CMTimeGetSeconds(cues[0].timeRange.start) == 0)
        #expect(abs(CMTimeGetSeconds(cues[0].timeRange.duration) - 2.0) < 0.0001)
    }

    @Test func handlesBrAsLineBreak() {
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div>
            <p begin="00:00:00.000" end="00:00:03.000">Line one<br/>Line two</p>
          </div></body>
        </tt>
        """
        let cues = try! CaptionParser.parseITT(doc)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Line one\nLine two")
    }

    @Test func flattensSpanStyling() {
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div>
            <p begin="00:00:00.000" end="00:00:02.000"><span style="bold">Hello</span> <span>world</span></p>
          </div></body>
        </tt>
        """
        let cues = try! CaptionParser.parseITT(doc)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello world")
    }

    @Test func concatenatesMultipleDivBlocks() {
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body>
            <div>
              <p begin="00:00:00.000" end="00:00:02.000">First</p>
            </div>
            <div>
              <p begin="00:00:02.000" end="00:00:04.000">Second</p>
            </div>
          </body>
        </tt>
        """
        let cues = try! CaptionParser.parseITT(doc)
        #expect(cues.map(\.text) == ["First", "Second"])
    }

    @Test func readsFrameRateFromRoot() {
        // Frame-count timestamps approximate at the document's declared frame rate.
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttp="http://www.w3.org/ns/ttml#parameter" ttp:frameRate="29.97">
          <body><div>
            <p begin="00:00:00:00" end="00:00:01:15">Frame</p>
          </div></body>
        </tt>
        """
        let cues = try! CaptionParser.parseITT(doc)
        #expect(cues.count == 1)
        let dur = CMTimeGetSeconds(cues[0].timeRange.duration)
        // begin = 0, end = 1 + 15/29.97 ≈ 1.5005s. Duration = 1.5005s.
        #expect(abs(dur - (1.0 + 15.0 / 29.97)) < 0.005)
    }

    @Test func toleratesTtPrefixedAttributes() {
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div>
            <p tt:begin="00:00:00.000" tt:end="00:00:02.000">Prefixed</p>
          </div></body>
        </tt>
        """
        let cues = try! CaptionParser.parseITT(doc)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Prefixed")
    }

    @Test func parsesEmptyBodyToEmptyArray() {
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div></div></body>
        </tt>
        """
        let cues = try! CaptionParser.parseITT(doc)
        #expect(cues.isEmpty)
    }

    // MARK: - parseITT — error paths

    @Test func throwsOnMalformedXML() {
        let doc = "<tt><body><div><p begin=\"0\" end=\"1\">unclosed"
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseITT(doc)
        }
    }

    @Test func throwsOnMalformedTimestamp() {
        let doc = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div>
            <p begin="garbage" end="00:00:02.000">X</p>
          </div></body>
        </tt>
        """
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseITT(doc)
        }
    }

    // MARK: - File loader smoke

    @Test func fileLoaderReadsITT() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".itt")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(itt: tmp)
        #expect(cues.count == 2)
    }

    @Test func fileLoaderThrowsOnMissingFile() async throws {
        let missing = URL(fileURLWithPath: "/dev/null/nonexistent.itt")
        await #expect(throws: CaptionParseError.self) {
            try await Caption.load(itt: missing)
        }
    }

    // MARK: - Auto-detect dispatch

    @Test func autoDetectDispatchesITT() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".itt")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 2)
    }

    @Test func autoDetectDispatchesITTCaseInsensitive() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ITT")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 2)
    }

    // MARK: - Writer helpers

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    @Test func formatsITTTimestamp() {
        #expect(CaptionAuthor.formatITTTimestamp(cmt(0)) == "00:00:00.000")
        #expect(CaptionAuthor.formatITTTimestamp(cmt(83.456)) == "00:01:23.456")
        #expect(CaptionAuthor.formatITTTimestamp(cmt(3725.5)) == "01:02:05.500")
    }

    @Test func xmlEscapeHandlesAllFiveEntities() {
        #expect(CaptionAuthor.xmlEscape("a & b < c > d \"e\" 'f'")
            == "a &amp; b &lt; c &gt; d &quot;e&quot; &apos;f&apos;")
    }

    @Test func xmlEscapeLeavesPlainTextUntouched() {
        #expect(CaptionAuthor.xmlEscape("hello world") == "hello world")
    }

    @Test func renderCueBodyConvertsNewlinesToBr() {
        #expect(CaptionAuthor.renderCueBody("Line one\nLine two") == "Line one<br/>Line two")
    }

    @Test func renderCueBodyEscapesAndConverts() {
        #expect(CaptionAuthor.renderCueBody("a < b\nc & d") == "a &lt; b<br/>c &amp; d")
    }

    // MARK: - renderITT

    @Test func renderITTHasXMLDeclarationAndHeader() {
        let cues = [Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2)))]
        let out = CaptionAuthor.renderITT(cues)
        #expect(out.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(out.contains("xmlns=\"http://www.w3.org/ns/ttml\""))
        #expect(out.contains("ttp:frameRate=\"30\""))
        #expect(out.contains("ttp:tickRate=\"1000\""))
    }

    @Test func renderITTEmitsOnePElementPerCue() {
        let cues = [
            Caption(text: "First", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "Second", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let out = CaptionAuthor.renderITT(cues)
        #expect(out.contains("<p begin=\"00:00:00.000\" end=\"00:00:02.000\">First</p>"))
        #expect(out.contains("<p begin=\"00:00:02.000\" end=\"00:00:05.000\">Second</p>"))
    }

    @Test func renderITTEscapesSpecialCharacters() {
        let cues = [Caption(text: "a & b < c", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1)))]
        let out = CaptionAuthor.renderITT(cues)
        #expect(out.contains("a &amp; b &lt; c"))
    }

    @Test func renderITTConvertsNewlinesToBr() {
        let cues = [Caption(text: "Line one\nLine two", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1)))]
        let out = CaptionAuthor.renderITT(cues)
        #expect(out.contains("Line one<br/>Line two"))
    }

    // MARK: - Round-trip

    @Test func roundTripPreservesPlainCaptions() {
        let cues = [
            Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "World", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let rendered = CaptionAuthor.renderITT(cues)
        let reparsed = try! CaptionParser.parseITT(rendered)
        #expect(reparsed.count == cues.count)
        for (a, b) in zip(cues, reparsed) {
            #expect(a.text == b.text)
            #expect(abs(CMTimeGetSeconds(a.timeRange.start) - CMTimeGetSeconds(b.timeRange.start)) < 0.001)
            #expect(abs(CMTimeGetSeconds(a.timeRange.duration) - CMTimeGetSeconds(b.timeRange.duration)) < 0.001)
        }
    }

    @Test func roundTripPreservesMultilineCaptions() {
        let cues = [
            Caption(text: "First\nSecond\nThird", timeRange: CMTimeRange(start: cmt(0), duration: cmt(3))),
        ]
        let rendered = CaptionAuthor.renderITT(cues)
        let reparsed = try! CaptionParser.parseITT(rendered)
        #expect(reparsed.count == 1)
        #expect(reparsed[0].text == "First\nSecond\nThird")
    }

    @Test func roundTripPreservesSpecialCharacters() {
        let cues = [
            Caption(text: "a & b < c > d", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
        ]
        let rendered = CaptionAuthor.renderITT(cues)
        let reparsed = try! CaptionParser.parseITT(rendered)
        #expect(reparsed.count == 1)
        #expect(reparsed[0].text == "a & b < c > d")
    }

    @Test func writerRoundTripsThroughDisk() async throws {
        let cues = [
            Caption(text: "Round", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1))),
            Caption(text: "Trip", timeRange: CMTimeRange(start: cmt(1), duration: cmt(2))),
        ]
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".itt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await CaptionAuthor.writeITT(cues, to: tmp)
        let reparsed = try await Caption.load(itt: tmp)
        #expect(reparsed.count == 2)
        #expect(reparsed.map(\.text) == ["Round", "Trip"])
    }
}
