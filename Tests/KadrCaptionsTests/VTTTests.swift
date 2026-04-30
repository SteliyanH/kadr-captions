import Testing
import CoreMedia
import Foundation
@testable import KadrCaptions

/// Tests for v0.1 Tier 2 — VTT parser, writer, and helpers.
struct VTTTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    // MARK: - parseVTTTimestamp

    @Test func parsesStandardVTTTimestamp() {
        let t = CaptionParser.parseVTTTimestamp("00:01:23.456")
        #expect(abs(CMTimeGetSeconds(t!) - 83.456) < 0.0001)
    }

    @Test func parsesShortFormVTTTimestamp() {
        // MM:SS.mmm without hour component (per WebVTT spec).
        let t = CaptionParser.parseVTTTimestamp("01:23.456")
        #expect(abs(CMTimeGetSeconds(t!) - 83.456) < 0.0001)
    }

    @Test func toleratesCommaSeparator() {
        let t = CaptionParser.parseVTTTimestamp("00:01:23,456")
        #expect(abs(CMTimeGetSeconds(t!) - 83.456) < 0.0001)
    }

    @Test func rejectsInvalidVTTTimestamp() {
        #expect(CaptionParser.parseVTTTimestamp("xx") == nil)
        #expect(CaptionParser.parseVTTTimestamp("00:00:00:00.000") == nil)
    }

    // MARK: - parseVTTTimestampLine

    @Test func parsesVTTTimestampLineWithoutCueSettings() {
        let r = CaptionParser.parseVTTTimestampLine("00:00:00.000 --> 00:00:02.500")
        #expect(r != nil)
        #expect(abs(CMTimeGetSeconds(r!.duration) - 2.5) < 0.0001)
    }

    @Test func stripsCueSettingsFromTimestampLine() {
        let r = CaptionParser.parseVTTTimestampLine(
            "00:00:00.000 --> 00:00:02.500 align:start position:0% line:20%"
        )
        #expect(r != nil)
        #expect(abs(CMTimeGetSeconds(r!.duration) - 2.5) < 0.0001)
    }

    // MARK: - stripVTTInlineTags

    @Test func stripsClassTags() {
        #expect(CaptionParser.stripVTTInlineTags("<c.classname>Hello</c>") == "Hello")
    }

    @Test func stripsStyleTags() {
        #expect(CaptionParser.stripVTTInlineTags("<i>italic</i> and <b>bold</b>") == "italic and bold")
    }

    @Test func stripsVoiceTags() {
        #expect(CaptionParser.stripVTTInlineTags("<v Speaker>Hello</v>") == "Hello")
    }

    @Test func stripsTimedTextMarkers() {
        #expect(CaptionParser.stripVTTInlineTags("First <00:00:01.500>Second") == "First Second")
    }

    @Test func leavesPlainTextUntouched() {
        #expect(CaptionParser.stripVTTInlineTags("plain text") == "plain text")
    }

    @Test func handlesUnclosedTagsGracefully() {
        // Properly closed tag, content after it preserved.
        #expect(CaptionParser.stripVTTInlineTags("<i>oops") == "oops")
        // Genuinely unclosed (no `>` to end the tag): everything after `<` is dropped.
        #expect(CaptionParser.stripVTTInlineTags("text <i oops") == "text ")
    }

    // MARK: - isVTTSkipBlockHeader

    @Test func recognizesSkipBlockHeaders() {
        #expect(CaptionParser.isVTTSkipBlockHeader("NOTE"))
        #expect(CaptionParser.isVTTSkipBlockHeader("NOTE this is a comment"))
        #expect(CaptionParser.isVTTSkipBlockHeader("REGION"))
        #expect(CaptionParser.isVTTSkipBlockHeader("STYLE"))
    }

    @Test func nonSkipHeadersReturnFalse() {
        #expect(!CaptionParser.isVTTSkipBlockHeader("00:00:00.000 --> 00:00:01.000"))
        #expect(!CaptionParser.isVTTSkipBlockHeader("NOTES"))     // not a real header
        #expect(!CaptionParser.isVTTSkipBlockHeader("regular cue text"))
    }

    // MARK: - parseVTT — header

    @Test func throwsOnMissingHeader() {
        let body = "00:00:00.000 --> 00:00:01.000\nText\n"
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseVTT(body)
        }
    }

    @Test func acceptsBareWEBVTTHeader() {
        let body = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nHello\n"
        let cues = try! CaptionParser.parseVTT(body)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello")
    }

    @Test func acceptsWEBVTTHeaderWithDescription() {
        let body = "WEBVTT - Subtitles in English\n\n00:00:00.000 --> 00:00:02.000\nHi\n"
        let cues = try! CaptionParser.parseVTT(body)
        #expect(cues.count == 1)
    }

    @Test func throwsOnEmptyContent() {
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseVTT("")
        }
    }

    // MARK: - parseVTT — cue blocks

    @Test func parsesSingleCue() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        Hello world
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello world")
    }

    @Test func parsesMultipleCues() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        First

        00:00:02.000 --> 00:00:04.000
        Second
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.map(\.text) == ["First", "Second"])
    }

    @Test func skipsCueIdentifierBeforeTimestamp() {
        let vtt = """
        WEBVTT

        cue-1
        00:00:00.000 --> 00:00:02.000
        Hello
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello")
    }

    @Test func skipsNOTEBlocks() {
        let vtt = """
        WEBVTT

        NOTE This is a comment
        with multiple lines
        of comment text

        00:00:00.000 --> 00:00:02.000
        Hello
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello")
    }

    @Test func skipsREGIONBlocks() {
        let vtt = """
        WEBVTT

        REGION
        id:my-region
        width:100%

        00:00:00.000 --> 00:00:02.000
        Hello
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.count == 1)
    }

    @Test func skipsSTYLEBlocks() {
        let vtt = """
        WEBVTT

        STYLE
        ::cue { color: red; }

        00:00:00.000 --> 00:00:02.000
        Hello
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.count == 1)
    }

    @Test func stripsCueSettingsAndInlineStyles() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500 align:start position:0%
        <c.bold>Hello</c> <i>world</i>
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello world")
        #expect(abs(CMTimeGetSeconds(cues[0].timeRange.duration) - 2.5) < 0.0001)
    }

    @Test func parsesMultiLineCueWithStyles() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:03.000
        <i>First</i> line
        <b>Second</b> line
        """
        let cues = try! CaptionParser.parseVTT(vtt)
        #expect(cues[0].text == "First line\nSecond line")
    }

    // MARK: - Writer

    @Test func formatsVTTTimestamp() {
        #expect(CaptionAuthor.formatVTTTimestamp(cmt(0)) == "00:00:00.000")
        #expect(CaptionAuthor.formatVTTTimestamp(cmt(83.456)) == "00:01:23.456")
    }

    @Test func renderVTTIncludesHeader() {
        let cues = [Caption(text: "Hi", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1)))]
        let out = CaptionAuthor.renderVTT(cues)
        #expect(out.hasPrefix("WEBVTT\n\n"))
        #expect(out.contains("00:00:00.000 --> 00:00:01.000\nHi\n"))
    }

    @Test func roundTripPreservesCaptions() {
        let cues = [
            Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "Multi\nline", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let rendered = CaptionAuthor.renderVTT(cues)
        let reparsed = try! CaptionParser.parseVTT(rendered)
        #expect(reparsed.count == cues.count)
        for (a, b) in zip(cues, reparsed) {
            #expect(a.text == b.text)
            #expect(abs(CMTimeGetSeconds(a.timeRange.start) - CMTimeGetSeconds(b.timeRange.start)) < 0.001)
        }
    }

    // MARK: - File loader smoke

    @Test func fileLoaderReadsUTF8VTT() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".vtt")
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nHello\n"
        try vtt.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(vtt: tmp)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello")
    }

    @Test func writerRoundTripsThroughDisk() async throws {
        let cues = [
            Caption(text: "Round", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1))),
            Caption(text: "Trip", timeRange: CMTimeRange(start: cmt(1), duration: cmt(2))),
        ]
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".vtt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await CaptionAuthor.writeVTT(cues, to: tmp)
        let reparsed = try await Caption.load(vtt: tmp)
        #expect(reparsed.map(\.text) == ["Round", "Trip"])
    }
}
