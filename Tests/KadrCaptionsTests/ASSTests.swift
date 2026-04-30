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
}
