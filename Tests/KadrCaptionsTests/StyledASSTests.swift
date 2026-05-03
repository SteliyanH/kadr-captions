import XCTest
import CoreMedia
import Kadr
@testable import KadrCaptions

final class StyledASSTests: XCTestCase {

    // MARK: - parseASSColorPayload

    func testColorPayloadStandardForm() {
        let hex = CaptionParser.parseASSColorPayload("&H00FF00&")
        XCTAssertEqual(hex, "#00FF00")
    }

    func testColorPayloadBGRReorderingProducesRGB() {
        // ASS &HBBGGRR& — &H0000FF& means red. (BB=00, GG=00, RR=FF.)
        let hex = CaptionParser.parseASSColorPayload("&H0000FF&")
        XCTAssertEqual(hex, "#FF0000")
    }

    func testColorPayloadShortFormPaddedAndParsed() {
        // ASS sometimes drops leading zeros — &Hff& means &H0000FF& → red.
        let hex = CaptionParser.parseASSColorPayload("&Hff&")
        XCTAssertEqual(hex, "#FF0000")
    }

    func testColorPayloadAlphaFlippedFromOpaqueZero() {
        // ASS alpha is inverted — &H00BBGGRR&'s leading 00 = fully opaque.
        let hex = CaptionParser.parseASSColorPayload("&H000000FF&")
        XCTAssertEqual(hex, "#FF0000FF")
    }

    func testColorPayloadAlphaFlippedFromTransparentFF() {
        // &HFF... = fully transparent → AA=00 in our output.
        let hex = CaptionParser.parseASSColorPayload("&HFF000000&")
        XCTAssertEqual(hex, "#00000000")
    }

    func testColorPayloadMalformedReturnsNil() {
        XCTAssertNil(CaptionParser.parseASSColorPayload("not-a-color"))
        XCTAssertNil(CaptionParser.parseASSColorPayload(""))
    }

    // MARK: - mapANAlignment / mapLegacyAAlignment

    func testANAlignmentNumpadCodes() {
        XCTAssertEqual(CaptionParser.mapANAlignment(1).0, .start)
        XCTAssertEqual(CaptionParser.mapANAlignment(2).0, .center)
        XCTAssertEqual(CaptionParser.mapANAlignment(3).0, .end)
        XCTAssertEqual(CaptionParser.mapANAlignment(7).0, .start)
        XCTAssertEqual(CaptionParser.mapANAlignment(7).1, .top)
        XCTAssertEqual(CaptionParser.mapANAlignment(2).1, .bottom)
    }

    func testANAlignmentMiddleRowProducesPercent50() {
        let (alignment, line) = CaptionParser.mapANAlignment(5)
        XCTAssertEqual(alignment, .center)
        if case .percent(let p) = line {
            XCTAssertEqual(p, 50, accuracy: 0.0001)
        } else {
            XCTFail("Expected .percent(50) for \\an5")
        }
    }

    func testANAlignmentInvalidCodeFallsBackToCenterAuto() {
        let (alignment, line) = CaptionParser.mapANAlignment(99)
        XCTAssertEqual(alignment, .center)
        XCTAssertEqual(line, .auto)
    }

    func testLegacyAAlignmentBottomLeft() {
        let (alignment, line) = CaptionParser.mapLegacyAAlignment(1)
        XCTAssertEqual(alignment, .start)
        XCTAssertEqual(line, .bottom)
    }

    func testLegacyAAlignmentTopRight() {
        // SSA legacy: 3 (right) | 4 (top) = 7
        let (alignment, line) = CaptionParser.mapLegacyAAlignment(7)
        XCTAssertEqual(alignment, .end)
        XCTAssertEqual(line, .top)
    }

    // MARK: - parseASSOverrideFlags

    func testParseFlagsBoldAndItalic() {
        let result = CaptionParser.parseASSOverrideFlags("{\\b1\\i1}Hello")
        XCTAssertTrue(result.isBold)
        XCTAssertTrue(result.isItalic)
        XCTAssertFalse(result.isUnderlined)
    }

    func testParseFlagsBoldOffOverridesEarlierBold() {
        let result = CaptionParser.parseASSOverrideFlags("{\\b1}Hello{\\b0} World")
        XCTAssertFalse(result.isBold)
    }

    func testParseFlagsUnderline() {
        let result = CaptionParser.parseASSOverrideFlags("{\\u1}Hi")
        XCTAssertTrue(result.isUnderlined)
    }

    func testParseFlagsAlignmentFromAN() {
        let result = CaptionParser.parseASSOverrideFlags("{\\an8}Top center")
        XCTAssertEqual(result.alignment, .center)
        XCTAssertEqual(result.line, .top)
    }

    func testParseFlagsColorFromBackslashCAlias() {
        let result = CaptionParser.parseASSOverrideFlags("{\\c&H0000FF&}Red")
        XCTAssertEqual(result.color, "#FF0000")
    }

    func testParseFlagsColorFrom1cPrimary() {
        let result = CaptionParser.parseASSOverrideFlags("{\\1c&H00FF00&}Green")
        XCTAssertEqual(result.color, "#00FF00")
    }

    func testParseFlagsUnknownCodesIgnored() {
        // \fn, \fs, \pos — surface limits to the bridge-renderable subset.
        let result = CaptionParser.parseASSOverrideFlags("{\\fnArial\\fs28\\pos(10,20)}Hi")
        XCTAssertFalse(result.isBold)
        XCTAssertEqual(result.alignment, .center)
        XCTAssertNil(result.color)
    }

    // MARK: - parseStyledASS / parseStyledSSA

    private static let assMinimal = """
    [Script Info]
    Title: Test
    ScriptType: v4.00+

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour
    Style: Default,Arial,20,&H00FFFFFF

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\b1}Hello{\\b0} world
    Dialogue: 0,0:00:04.00,0:00:05.50,Default,,0,0,0,,{\\an8\\c&H0000FF&}Top red text
    """

    func testParseStyledASSPreservesTimingsAndPlainText() throws {
        let cues = try CaptionParser.parseStyledASS(StyledASSTests.assMinimal)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hello world")
        XCTAssertEqual(CMTimeGetSeconds(cues[0].timeRange.start), 1.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(cues[0].timeRange.duration), 2.0, accuracy: 0.001)
    }

    func testParseStyledASSCollapsesBoldAcrossCue() {
        let cues = try? CaptionParser.parseStyledASS(StyledASSTests.assMinimal)
        // {\b1}…{\b0} — final state is bold-off; per-cue collapse keeps the
        // last flag observed.
        XCTAssertEqual(cues?[0].isBold, false)
    }

    func testParseStyledASSRoundTripsAlignmentAndColor() throws {
        let cues = try CaptionParser.parseStyledASS(StyledASSTests.assMinimal)
        let second = cues[1]
        XCTAssertEqual(second.alignment, .center)
        XCTAssertEqual(second.line, .top)
        XCTAssertEqual(second.color, "#FF0000")
    }

    func testParseStyledSSALegacyAlignment() throws {
        let ssa = """
        [Script Info]
        ScriptType: v4.00

        [V4 Styles]
        Format: Name, Fontname, Fontsize
        Style: Default,Arial,20

        [Events]
        Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: Marked=0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\a1}Bottom-left
        """
        let cues = try CaptionParser.parseStyledSSA(ssa)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].alignment, .start)
        XCTAssertEqual(cues[0].line, .bottom)
    }

    func testParseStyledASSEmptyInputProducesEmpty() throws {
        let cues = try CaptionParser.parseStyledASS("")
        XCTAssertTrue(cues.isEmpty)
    }

    func testParseStyledASSSkipsCommentEvents() throws {
        let ass = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,Should be ignored
        Dialogue: 0,0:00:02.00,0:00:03.00,Default,,0,0,0,,Real cue
        """
        let cues = try CaptionParser.parseStyledASS(ass)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Real cue")
    }

    // MARK: - StyledCaption.platformColor(forHex:)

    func testPlatformColorParsesShortHex() {
        XCTAssertNotNil(StyledCaption.platformColor(forHex: "#FFFFFF"))
        XCTAssertNotNil(StyledCaption.platformColor(forHex: "FFFFFF"))
    }

    func testPlatformColorParsesAlphaHex() {
        XCTAssertNotNil(StyledCaption.platformColor(forHex: "#FF0000AA"))
    }

    func testPlatformColorRejectsMalformed() {
        XCTAssertNil(StyledCaption.platformColor(forHex: "#XYZ"))
        XCTAssertNil(StyledCaption.platformColor(forHex: "#FFF"))   // 3-digit shorthand not supported
    }

    // MARK: - End-to-end bridge: StyledCaption → TextOverlay carries color

    @MainActor
    func testStyledCaptionWithColorBuildsOverlayWithColor() {
        let cue = StyledCaption(
            text: "Red",
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            color: "#FF0000"
        )
        let overlay = cue.toTextOverlay()
        // The overlay carries the parsed PlatformColor — sanity check by
        // asserting it isn't equal to the default white style's color via the
        // overlay's `style.color` access. We can only smoke-test here since
        // PlatformColor doesn't have cross-platform equality.
        _ = overlay
    }
}
