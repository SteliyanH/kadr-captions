import Testing
import CoreMedia
import Foundation
@testable import KadrCaptions

/// Tests for v0.4 Tier 1 — ASS / SSA parsers + helpers + auto-detect dispatch update.
struct ASSTests {

    // MARK: - parseASSTimestamp

    @Test func parsesStandardTimestamp() {
        let t = CaptionParser.parseASSTimestamp("0:01:23.45")
        #expect(abs(CMTimeGetSeconds(t!) - 83.45) < 0.0001)
    }

    @Test func parsesTimestampWithoutCentiseconds() {
        let t = CaptionParser.parseASSTimestamp("0:01:23")
        #expect(abs(CMTimeGetSeconds(t!) - 83.0) < 0.0001)
    }

    @Test func parsesShortCentisecondsByPadding() {
        // "0:00:01.5" should be 1.50 seconds (one-digit cs padded to two).
        let t = CaptionParser.parseASSTimestamp("0:00:01.5")
        #expect(abs(CMTimeGetSeconds(t!) - 1.5) < 0.0001)
    }

    @Test func parsesTwoDigitCentisecondsExactly() {
        let t = CaptionParser.parseASSTimestamp("0:00:01.50")
        #expect(abs(CMTimeGetSeconds(t!) - 1.5) < 0.0001)
    }

    @Test func parsesUnpaddedHour() {
        // ASS hour digit is not zero-padded.
        let t = CaptionParser.parseASSTimestamp("1:00:00.00")
        #expect(abs(CMTimeGetSeconds(t!) - 3600.0) < 0.0001)
    }

    @Test func rejectsInvalidTimestamp() {
        #expect(CaptionParser.parseASSTimestamp("garbage") == nil)
        #expect(CaptionParser.parseASSTimestamp("01:23") == nil)
        #expect(CaptionParser.parseASSTimestamp("aa:bb:cc") == nil)
    }

    // MARK: - splitASSDialogue

    @Test func splitsSimpleDialogue() {
        let parts = CaptionParser.splitASSDialogue(
            "0,0:00:00.00,0:00:02.50,Default,,0,0,0,,Hello",
            columnCount: 10
        )
        #expect(parts.count == 10)
        #expect(parts[1] == "0:00:00.00")
        #expect(parts[2] == "0:00:02.50")
        #expect(parts[9] == "Hello")
    }

    @Test func preservesCommasInTextField() {
        let parts = CaptionParser.splitASSDialogue(
            "0,0:00:00.00,0:00:02.50,Default,,0,0,0,,Hello, world, more",
            columnCount: 10
        )
        #expect(parts.count == 10)
        #expect(parts[9] == "Hello, world, more")
    }

    @Test func returnsEmptyForZeroColumnCount() {
        let parts = CaptionParser.splitASSDialogue("anything", columnCount: 0)
        #expect(parts.isEmpty)
    }

    // MARK: - stripASSOverrides

    @Test func stripsBoldOverride() {
        #expect(CaptionParser.stripASSOverrides("{\\b1}Hello{\\b0}") == "Hello")
    }

    @Test func stripsColorOverride() {
        #expect(CaptionParser.stripASSOverrides("{\\c&HFFFFFF&}Bright") == "Bright")
    }

    @Test func stripsKaraokeTags() {
        #expect(CaptionParser.stripASSOverrides("{\\k50}Hel{\\k20}lo") == "Hello")
    }

    @Test func convertsBackslashNToNewline() {
        #expect(CaptionParser.stripASSOverrides("Line one\\NLine two") == "Line one\nLine two")
    }

    @Test func convertsLowercaseBackslashNToNewline() {
        #expect(CaptionParser.stripASSOverrides("Line one\\nLine two") == "Line one\nLine two")
    }

    @Test func convertsHardSpaceToSpace() {
        #expect(CaptionParser.stripASSOverrides("Hello\\hworld") == "Hello world")
    }

    @Test func leavesPlainTextUntouched() {
        #expect(CaptionParser.stripASSOverrides("plain text") == "plain text")
    }

    @Test func handlesMixedOverridesAndText() {
        let raw = "{\\b1}Hello{\\b0}\\N{\\i1}world{\\i0}"
        #expect(CaptionParser.stripASSOverrides(raw) == "Hello\nworld")
    }

    // MARK: - parseASS — happy paths

    private let minimalDoc = """
    [Script Info]
    Title: Test
    ScriptType: v4.00+

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour
    Style: Default,Arial,20,&H00FFFFFF

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:00.00,0:00:02.50,Default,,0,0,0,,Hello world
    Dialogue: 0,0:00:02.50,0:00:05.00,Default,,0,0,0,,Second line
    """

    @Test func parsesMinimalASSDoc() {
        let cues = try! CaptionParser.parseASS(minimalDoc)
        #expect(cues.count == 2)
        #expect(cues.map(\.text) == ["Hello world", "Second line"])
        #expect(CMTimeGetSeconds(cues[0].timeRange.start) == 0)
        #expect(abs(CMTimeGetSeconds(cues[0].timeRange.duration) - 2.5) < 0.0001)
    }

    @Test func parsesMultiLineCueViaBackslashN() {
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:03.00,Default,,0,0,0,,Line one\\NLine two
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Line one\nLine two")
    }

    @Test func stripsOverridesInCueText() {
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,{\\b1}Bold{\\b0} text
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues[0].text == "Bold text")
    }

    @Test func preservesCommasInCueText() {
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,One, two, three
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues[0].text == "One, two, three")
    }

    @Test func skipsCommentEvents() {
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,Hidden
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,Visible
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Visible")
    }

    @Test func skipsSemicolonComments() {
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        ; This is a comment
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,Visible
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues.count == 1)
    }

    @Test func returnsEmptyForMissingEventsSection() {
        let doc = """
        [Script Info]
        Title: No events
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues.isEmpty)
    }

    @Test func parseSSAUsesSameLogic() {
        // SSA accepts the same event format we test with ASS.
        let cues = try! CaptionParser.parseSSA(minimalDoc)
        #expect(cues.count == 2)
    }

    // MARK: - Error paths

    @Test func throwsOnMalformedTimestamp() {
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,garbage,0:00:02.00,Default,,0,0,0,,Bad
        """
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseASS(doc)
        }
    }

    @Test func dropsCueWithEndBeforeStart() {
        // Reverse-range cues are dropped silently rather than throwing.
        let doc = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:05.00,0:00:02.00,Default,,0,0,0,,Reversed
        Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,Forward
        """
        let cues = try! CaptionParser.parseASS(doc)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Forward")
    }

    // MARK: - File loader

    @Test func fileLoaderReadsASS() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ass")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(ass: tmp)
        #expect(cues.count == 2)
    }

    // MARK: - Auto-detect

    @Test func autoDetectDispatchesASS() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ass")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 2)
    }

    @Test func autoDetectDispatchesSSA() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ssa")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 2)
    }

    @Test func autoDetectDispatchesASSCaseInsensitive() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ASS")
        try minimalDoc.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 2)
    }

    // MARK: - Writer helpers

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    @Test func formatsASSTimestamp() {
        #expect(CaptionAuthor.formatASSTimestamp(cmt(0)) == "0:00:00.00")
        #expect(CaptionAuthor.formatASSTimestamp(cmt(83.45)) == "0:01:23.45")
        #expect(CaptionAuthor.formatASSTimestamp(cmt(3725.5)) == "1:02:05.50")
    }

    @Test func formatASSTimestampDoesNotZeroPadHour() {
        #expect(CaptionAuthor.formatASSTimestamp(cmt(7200)) == "2:00:00.00")
    }

    @Test func renderASSCueTextConvertsNewlinesToBackslashN() {
        #expect(CaptionAuthor.renderASSCueText("Line one\nLine two") == "Line one\\NLine two")
    }

    @Test func renderASSCueTextPassesPlainTextThrough() {
        #expect(CaptionAuthor.renderASSCueText("plain text") == "plain text")
    }

    // MARK: - renderASS

    @Test func renderASSHasExpectedHeader() {
        let cues = [Caption(text: "Hi", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1)))]
        let out = CaptionAuthor.renderASS(cues)
        #expect(out.contains("[Script Info]"))
        #expect(out.contains("ScriptType: v4.00+"))
        #expect(out.contains("[V4+ Styles]"))
        #expect(out.contains("[Events]"))
        #expect(out.contains("Format: Layer, Start, End, Style, Name"))
    }

    @Test func renderASSEmitsOneDialoguePerCue() {
        let cues = [
            Caption(text: "First", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "Second", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let out = CaptionAuthor.renderASS(cues)
        #expect(out.contains("Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,First"))
        #expect(out.contains("Dialogue: 0,0:00:02.00,0:00:05.00,Default,,0,0,0,,Second"))
    }

    @Test func renderASSConvertsNewlinesInCueText() {
        let cues = [Caption(text: "Line\nbreak", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1)))]
        let out = CaptionAuthor.renderASS(cues)
        #expect(out.contains(",Line\\Nbreak"))
    }

    // MARK: - renderSSA

    @Test func renderSSAUsesV400AndMarkedField() {
        let cues = [Caption(text: "Hi", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1)))]
        let out = CaptionAuthor.renderSSA(cues)
        #expect(out.contains("ScriptType: v4.00\n"))
        #expect(out.contains("[V4 Styles]"))
        #expect(out.contains("Format: Marked, Start, End, Style"))
        #expect(out.contains("Dialogue: Marked=0,"))
    }

    // MARK: - Round-trip

    @Test func roundTripsASSPreservesPlainCaptions() {
        let cues = [
            Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "World", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let rendered = CaptionAuthor.renderASS(cues)
        let reparsed = try! CaptionParser.parseASS(rendered)
        #expect(reparsed.count == cues.count)
        for (a, b) in zip(cues, reparsed) {
            #expect(a.text == b.text)
            #expect(abs(CMTimeGetSeconds(a.timeRange.start) - CMTimeGetSeconds(b.timeRange.start)) < 0.01)
            #expect(abs(CMTimeGetSeconds(a.timeRange.duration) - CMTimeGetSeconds(b.timeRange.duration)) < 0.01)
        }
    }

    @Test func roundTripsASSPreservesMultilineCaptions() {
        let cues = [
            Caption(text: "First\nSecond\nThird", timeRange: CMTimeRange(start: cmt(0), duration: cmt(3))),
        ]
        let rendered = CaptionAuthor.renderASS(cues)
        let reparsed = try! CaptionParser.parseASS(rendered)
        #expect(reparsed.count == 1)
        #expect(reparsed[0].text == "First\nSecond\nThird")
    }

    @Test func roundTripsASSPreservesCommasInText() {
        let cues = [
            Caption(text: "One, two, three", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
        ]
        let rendered = CaptionAuthor.renderASS(cues)
        let reparsed = try! CaptionParser.parseASS(rendered)
        #expect(reparsed[0].text == "One, two, three")
    }

    @Test func roundTripsSSAPreservesPlainCaptions() {
        let cues = [
            Caption(text: "Hello", timeRange: CMTimeRange(start: cmt(0), duration: cmt(2))),
            Caption(text: "World", timeRange: CMTimeRange(start: cmt(2), duration: cmt(3))),
        ]
        let rendered = CaptionAuthor.renderSSA(cues)
        let reparsed = try! CaptionParser.parseSSA(rendered)
        #expect(reparsed.count == cues.count)
        for (a, b) in zip(cues, reparsed) {
            #expect(a.text == b.text)
        }
    }

    // MARK: - File loader round-trip

    @Test func writerRoundTripsThroughDisk() async throws {
        let cues = [
            Caption(text: "Round", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1))),
            Caption(text: "Trip", timeRange: CMTimeRange(start: cmt(1), duration: cmt(2))),
        ]
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ass")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await CaptionAuthor.writeASS(cues, to: tmp)
        let reparsed = try await Caption.load(ass: tmp)
        #expect(reparsed.count == 2)
        #expect(reparsed.map(\.text) == ["Round", "Trip"])
    }

    @Test func ssaWriterRoundTripsThroughDisk() async throws {
        let cues = [
            Caption(text: "S", timeRange: CMTimeRange(start: cmt(0), duration: cmt(1))),
            Caption(text: "A", timeRange: CMTimeRange(start: cmt(1), duration: cmt(2))),
        ]
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".ssa")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await CaptionAuthor.writeSSA(cues, to: tmp)
        let reparsed = try await Caption.load(ssa: tmp)
        #expect(reparsed.count == 2)
    }
}
