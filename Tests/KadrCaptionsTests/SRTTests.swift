import Testing
import CoreMedia
import Foundation
@testable import KadrCaptions

/// Tests for v0.1 Tier 1 — SRT parser, writer, and timestamp helpers.
struct SRTTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    // MARK: - parseSRTTimestamp

    @Test func parsesStandardTimestamp() {
        let t = CaptionParser.parseSRTTimestamp("00:01:23,456")
        #expect(t != nil)
        #expect(abs(CMTimeGetSeconds(t!) - 83.456) < 0.0001)
    }

    @Test func parsesTimestampWithDotSeparator() {
        // Lenient on dot-separated milliseconds (some real-world files use VTT style).
        let t = CaptionParser.parseSRTTimestamp("00:01:23.456")
        #expect(abs(CMTimeGetSeconds(t!) - 83.456) < 0.0001)
    }

    @Test func parsesTimestampWithoutMilliseconds() {
        let t = CaptionParser.parseSRTTimestamp("00:01:23")
        #expect(abs(CMTimeGetSeconds(t!) - 83.0) < 0.0001)
    }

    @Test func parsesShortMillisecondsByPadding() {
        // "00:00:01,5" should become 1.500 seconds (one-digit ms padded).
        let t = CaptionParser.parseSRTTimestamp("00:00:01,5")
        #expect(abs(CMTimeGetSeconds(t!) - 1.5) < 0.0001)
    }

    @Test func parsesLongMillisecondsByTruncating() {
        let t = CaptionParser.parseSRTTimestamp("00:00:01,123456")
        #expect(abs(CMTimeGetSeconds(t!) - 1.123) < 0.0001)
    }

    @Test func rejectsInvalidTimestamp() {
        #expect(CaptionParser.parseSRTTimestamp("garbage") == nil)
        #expect(CaptionParser.parseSRTTimestamp("00:01") == nil)
        #expect(CaptionParser.parseSRTTimestamp("aa:bb:cc,dd") == nil)
    }

    // MARK: - parseSRTTimestampLine

    @Test func parsesStandardTimestampLine() {
        let r = CaptionParser.parseSRTTimestampLine("00:00:00,000 --> 00:00:02,500")
        #expect(r != nil)
        #expect(CMTimeGetSeconds(r!.start) == 0)
        #expect(abs(CMTimeGetSeconds(r!.duration) - 2.5) < 0.0001)
    }

    @Test func rejectsTimestampLineMissingArrow() {
        #expect(CaptionParser.parseSRTTimestampLine("00:00:00,000 00:00:02,500") == nil)
    }

    @Test func rejectsTimestampLineWithReverseRange() {
        // End before start → zero or negative duration → reject.
        #expect(CaptionParser.parseSRTTimestampLine("00:00:05,000 --> 00:00:02,000") == nil)
    }

    // MARK: - parseSRT — happy paths

    @Test func parsesSingleCue() {
        let srt = """
        1
        00:00:00,000 --> 00:00:02,500
        Hello world

        """
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 1)
        #expect(captions[0].text == "Hello world")
        #expect(CMTimeGetSeconds(captions[0].timeRange.start) == 0)
    }

    @Test func parsesMultipleCues() {
        let srt = """
        1
        00:00:00,000 --> 00:00:02,000
        First

        2
        00:00:02,000 --> 00:00:04,000
        Second

        3
        00:00:04,000 --> 00:00:06,000
        Third
        """
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 3)
        #expect(captions.map(\.text) == ["First", "Second", "Third"])
    }

    @Test func parsesMultiLineCue() {
        let srt = """
        1
        00:00:00,000 --> 00:00:03,000
        Line one
        Line two
        Line three

        """
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 1)
        #expect(captions[0].text == "Line one\nLine two\nLine three")
    }

    @Test func parsesCRLFLineEndings() {
        let srt = "1\r\n00:00:00,000 --> 00:00:02,000\r\nHello\r\n\r\n"
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 1)
        #expect(captions[0].text == "Hello")
    }

    @Test func parsesMixedLineEndings() {
        let srt = "1\r\n00:00:00,000 --> 00:00:02,000\nHello\r\n\n"
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 1)
    }

    @Test func stripsUTF8BOM() {
        let srt = "\u{FEFF}1\n00:00:00,000 --> 00:00:02,000\nHello\n"
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 1)
        #expect(captions[0].text == "Hello")
    }

    @Test func acceptsMissingCueIndex() {
        // Lenient: cue index line absent — go straight from blank to timestamp.
        let srt = """
        00:00:00,000 --> 00:00:02,000
        No index here

        """
        let captions = try! CaptionParser.parseSRT(srt)
        #expect(captions.count == 1)
        #expect(captions[0].text == "No index here")
    }

    @Test func parsesEmptyContentToEmptyArray() {
        #expect(try! CaptionParser.parseSRT("").isEmpty)
        #expect(try! CaptionParser.parseSRT("   \n\n\n").isEmpty)
    }

    // MARK: - parseSRT — error paths

    @Test func throwsOnMalformedTimestamp() {
        let srt = """
        1
        not a timestamp
        Text

        """
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseSRT(srt)
        }
    }

    // MARK: - Writer

    @Test func formatsTimestampInSRTForm() {
        #expect(CaptionAuthor.formatSRTTimestamp(cmt(0)) == "00:00:00,000")
        #expect(CaptionAuthor.formatSRTTimestamp(cmt(83.456)) == "00:01:23,456")
        #expect(CaptionAuthor.formatSRTTimestamp(cmt(3725.5)) == "01:02:05,500")
    }

    @Test func renderSRTProducesExpectedString() {
        let cues = [
            Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "World", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let out = CaptionAuthor.renderSRT(cues)
        #expect(out.contains("1\n00:00:00,000 --> 00:00:02,000\nHello\n"))
        #expect(out.contains("2\n00:00:02,000 --> 00:00:05,000\nWorld\n"))
    }

    @Test func roundTripPreservesCaptions() {
        let cues = [
            Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "Multi\nline\ntext", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
            Caption(text: "Third", timeRange: CMTimeRange(start: cmt(5.5), duration: cmt(1.5))),
        ]
        let rendered = CaptionAuthor.renderSRT(cues)
        let reparsed = try! CaptionParser.parseSRT(rendered)
        #expect(reparsed.count == cues.count)
        for (a, b) in zip(cues, reparsed) {
            #expect(a.text == b.text)
            #expect(abs(CMTimeGetSeconds(a.timeRange.start) - CMTimeGetSeconds(b.timeRange.start)) < 0.001)
            #expect(abs(CMTimeGetSeconds(a.timeRange.duration) - CMTimeGetSeconds(b.timeRange.duration)) < 0.001)
        }
    }

    // MARK: - File loader smoke

    @Test func fileLoaderReadsUTF8() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".srt")
        let srt = "1\n00:00:00,000 --> 00:00:02,000\nHello UTF-8\n"
        try srt.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(srt: tmp)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello UTF-8")
    }

    @Test func fileLoaderFallsBackToWindows1252() async throws {
        // Build content with a Latin-1 character that's invalid as raw UTF-8 bytes.
        // 0xE9 = "é" in Windows-1252 / Latin-1, but is an invalid UTF-8 lead byte by itself.
        let bytes: [UInt8] = Array("1\n00:00:00,000 --> 00:00:02,000\nCaf".utf8)
            + [0xE9]
            + Array("\n".utf8)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".srt")
        try Data(bytes).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(srt: tmp)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Café")
    }

    @Test func fileLoaderThrowsOnMissingFile() async throws {
        let missing = URL(fileURLWithPath: "/dev/null/nonexistent.srt")
        await #expect(throws: CaptionParseError.self) {
            try await Caption.load(srt: missing)
        }
    }

    @Test func writerRoundTripsThroughDisk() async throws {
        let cues = [
            Caption(text: "Round", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1))),
            Caption(text: "Trip", timeRange: CMTimeRange(start: cmt(1), duration: cmt(2))),
        ]
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".srt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await CaptionAuthor.writeSRT(cues, to: tmp)
        let reparsed = try await Caption.load(srt: tmp)
        #expect(reparsed.count == 2)
        #expect(reparsed.map(\.text) == ["Round", "Trip"])
    }
}
