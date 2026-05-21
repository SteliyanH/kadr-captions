import XCTest
import CoreMedia
@testable import KadrCaptions

/// v0.6 Tier 1 — tests for the `.idx` VobSub parser. No fixture file:
/// every `.idx` body is synthesized inline so the test surface stays
/// portable and the fixture format is documented alongside each
/// assertion.
final class VobSubTests: XCTestCase {

    // MARK: - End-to-end parser

    func testParseSingleCue() throws {
        let body = """
        id: en, index: 0
        palette: 000000, ffffff
        timestamp: 00:00:01:500, filepos: 0x00000400
        """
        let index = try CaptionParser.parseVobSubIndex(body)
        XCTAssertEqual(index.language, "en")
        XCTAssertEqual(index.cues.count, 1)
        XCTAssertEqual(index.cues[0].fileOffset, 0x400)
        XCTAssertEqual(CMTimeGetSeconds(index.cues[0].start), 1.5, accuracy: 0.001)
    }

    func testParseMultipleCues() throws {
        let body = """
        id: de, index: 0
        timestamp: 00:00:00:000, filepos: 0x00000000
        timestamp: 00:00:05:250, filepos: 0x00001A00
        timestamp: 00:01:00:000, filepos: 0x00003C00
        """
        let index = try CaptionParser.parseVobSubIndex(body)
        XCTAssertEqual(index.language, "de")
        XCTAssertEqual(index.cues.count, 3)
        XCTAssertEqual(index.cues[1].fileOffset, 0x1A00)
        XCTAssertEqual(CMTimeGetSeconds(index.cues[2].start), 60, accuracy: 0.001)
    }

    func testCommentsAndBlankLinesAreSkipped() throws {
        let body = """
        # archived from DVD release
        id: en

        # palette block
        palette: 808080, 000000

        timestamp: 00:00:02:000, filepos: 0x00000800
        """
        let index = try CaptionParser.parseVobSubIndex(body)
        XCTAssertEqual(index.cues.count, 1)
        XCTAssertNotNil(index.paletteHex)
    }

    func testUnrecognizedDirectivesAreIgnored() throws {
        // size:, org:, scale:, etc. are layout metadata we don't surface
        // in v0.6. The parser must skip them silently rather than failing.
        let body = """
        id: en, index: 0
        size: 720x480
        org: 0, 0
        scale: 100%, 100%
        alpha: 100%
        timestamp: 00:00:03:000, filepos: 0x00001000
        """
        let index = try CaptionParser.parseVobSubIndex(body)
        XCTAssertEqual(index.cues.count, 1)
    }

    func testMalformedTimestampThrows() {
        let body = """
        id: en
        timestamp: bogus, filepos: 0x00000400
        """
        XCTAssertThrowsError(try CaptionParser.parseVobSubIndex(body)) { error in
            guard case CaptionParseError.malformedTimestamp = error else {
                return XCTFail("Expected malformedTimestamp, got \(error)")
            }
        }
    }

    func testMissingFileposThrows() {
        let body = """
        timestamp: 00:00:01:000
        """
        XCTAssertThrowsError(try CaptionParser.parseVobSubIndex(body))
    }

    // MARK: - Palette parsing

    func testPalettePadsToSixteenEntries() {
        let palette = CaptionParser.parseVobSubPalette("palette: 000000, ffffff, 808080")
        XCTAssertEqual(palette?.count, 16)
        XCTAssertEqual(palette?[0], "000000")
        XCTAssertEqual(palette?[3], "000000", "Padding entries should be black")
    }

    func testPaletteTruncatesAtSixteen() {
        let entries = (0..<20).map { _ in "abcdef" }.joined(separator: ", ")
        let palette = CaptionParser.parseVobSubPalette("palette: \(entries)")
        XCTAssertEqual(palette?.count, 16)
    }

    func testPaletteRejectsNonHexEntries() {
        // The parser silently drops invalid entries before padding. Two
        // valid + one garbage → two valid kept, then padded to 16.
        let palette = CaptionParser.parseVobSubPalette("palette: 000000, NOTHEX, ffffff")
        XCTAssertEqual(palette?.count, 16)
        XCTAssertEqual(palette?[0], "000000")
        XCTAssertEqual(palette?[1], "ffffff")
    }

    // MARK: - Language parsing

    func testLanguageExtractsTwoLetterCode() {
        XCTAssertEqual(CaptionParser.parseVobSubLanguage("id: en, index: 0"), "en")
        XCTAssertEqual(CaptionParser.parseVobSubLanguage("id: pt-BR, index: 0"), "pt-BR")
    }

    func testLanguageReturnsNilForEmpty() {
        XCTAssertNil(CaptionParser.parseVobSubLanguage("id: , index: 0"))
    }

    // MARK: - Timestamp parsing

    func testTimestampHandlesAllComponents() {
        let time = CaptionParser.parseVobSubTimestamp("01:23:45:678")
        let expected = ((1 * 3600) + (23 * 60) + 45) * 1000 + 678
        XCTAssertEqual(time?.value, CMTimeValue(expected))
        XCTAssertEqual(time?.timescale, 1000)
    }

    func testTimestampRejectsInvalidFormat() {
        // SRT uses comma, VTT uses dot, VobSub uses colon. Cross-format
        // contamination must fail.
        XCTAssertNil(CaptionParser.parseVobSubTimestamp("00:00:01.500"))
        XCTAssertNil(CaptionParser.parseVobSubTimestamp("00:00:01,500"))
    }

    // MARK: - Caption bridge

    func testFromVobSubIndexInfersDurationFromNextCue() {
        let index = VobSubIndex(
            language: nil,
            paletteHex: nil,
            cues: [
                VobSubCue(start: CMTime(value: 1000, timescale: 1000), fileOffset: 0),
                VobSubCue(start: CMTime(value: 5000, timescale: 1000), fileOffset: 100),
            ]
        )
        let captions = Caption.fromVobSubIndex(index)
        XCTAssertEqual(captions.count, 2)
        XCTAssertEqual(CMTimeGetSeconds(captions[0].timeRange.duration), 4, accuracy: 0.001)
    }

    func testFromVobSubIndexAppliesTrailingDurationForLastCue() {
        // The `.idx` format has no end-time field — the last cue stays
        // on screen for the caller-supplied trailing duration.
        let index = VobSubIndex(
            language: nil,
            paletteHex: nil,
            cues: [VobSubCue(start: .zero, fileOffset: 0)]
        )
        let captions = Caption.fromVobSubIndex(
            index,
            trailingDuration: CMTime(value: 3000, timescale: 1000)
        )
        XCTAssertEqual(CMTimeGetSeconds(captions[0].timeRange.duration), 3, accuracy: 0.001)
    }

    func testFromVobSubIndexDefaultsPlaceholderEmpty() {
        // Empty string is the documented "image-based; no text extracted"
        // signal. Consumers that want a visible badge pass their own
        // placeholderText.
        let index = VobSubIndex(
            language: nil,
            paletteHex: nil,
            cues: [VobSubCue(start: .zero, fileOffset: 0)]
        )
        XCTAssertEqual(Caption.fromVobSubIndex(index)[0].text, "")
    }
}
