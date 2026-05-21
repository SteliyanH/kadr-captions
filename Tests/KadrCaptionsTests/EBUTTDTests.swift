import XCTest
import CoreMedia
@testable import KadrCaptions

/// v0.6 Tier 3 — tests for the EBU-TT-D parser. Fixtures are synthesized
/// inline; the XML structure mirrors real BBC / EBU broadcast samples
/// (minimal valid root + body + div + p cues).
final class EBUTTDTests: XCTestCase {

    // MARK: - Time parser

    func testParseTimeWithFractionalSeconds() {
        let time = CaptionParser.parseEBUTTDTime("00:00:01.500")
        XCTAssertEqual(time?.seconds ?? 0, 1.5, accuracy: 0.001)
    }

    func testParseTimeWithoutFractionalSeconds() {
        let time = CaptionParser.parseEBUTTDTime("01:02:03")
        let expected = Double(1 * 3600 + 2 * 60 + 3)
        XCTAssertEqual(time?.seconds ?? 0, expected, accuracy: 0.001)
    }

    func testParseTimeRejectsFrameCount() {
        // iTT permits HH:MM:SS:FF; EBU-TT-D explicitly forbids it. Crucial
        // strictness — a file that round-trips through both parsers must
        // produce different results.
        XCTAssertNil(CaptionParser.parseEBUTTDTime("00:00:01:15"))
    }

    func testParseTimeRejectsSuffixForms() {
        // The broader TTML spec allows `1.5s` and `1500ms`; EBU-TT-D
        // restricts to clock form.
        XCTAssertNil(CaptionParser.parseEBUTTDTime("1.5s"))
        XCTAssertNil(CaptionParser.parseEBUTTDTime("1500ms"))
    }

    func testParseTimeRejectsInvalidInput() {
        XCTAssertNil(CaptionParser.parseEBUTTDTime("not-a-time"))
        XCTAssertNil(CaptionParser.parseEBUTTDTime(""))
        XCTAssertNil(CaptionParser.parseEBUTTDTime("00:00"))
    }

    // MARK: - End-to-end document parsing

    func testParseMinimalDocument() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"
            xmlns:tts="http://www.w3.org/ns/ttml#styling"
            xmlns:ebuttm="urn:ebu:tt:metadata"
            xmlns:ebutts="urn:ebu:tt:style"
            xml:lang="en">
            <body>
                <div>
                    <p begin="00:00:01.000" end="00:00:03.500">Hello world</p>
                </div>
            </body>
        </tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions[0].text, "Hello world")
        XCTAssertEqual(captions[0].timeRange.start.seconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(captions[0].timeRange.duration.seconds, 2.5, accuracy: 0.001)
    }

    func testParseMultipleCues() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en">
            <body><div>
                <p begin="00:00:01.000" end="00:00:02.000">First</p>
                <p begin="00:00:03.000" end="00:00:04.500">Second</p>
                <p begin="00:00:05.000" end="00:00:06.000">Third</p>
            </div></body>
        </tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions.count, 3)
        XCTAssertEqual(captions[1].text, "Second")
    }

    func testBrElementInsertsNewline() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en">
            <body><div>
                <p begin="00:00:01.000" end="00:00:03.000">Line one<br/>Line two</p>
            </div></body>
        </tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions[0].text, "Line one\nLine two")
    }

    func testEBUMetadataAndStyleBlocksAreSkipped() throws {
        // Real EBU-TT-D files carry <ebuttm:documentMetadata> + <ebutts:style>
        // blocks in the head. The parser strips them silently — only <p>
        // cues become Captions.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"
            xmlns:ebuttm="urn:ebu:tt:metadata"
            xmlns:ebutts="urn:ebu:tt:style"
            xml:lang="en">
            <head>
                <metadata>
                    <ebuttm:documentMetadata>
                        <ebuttm:documentEbuttVersion>v1.0</ebuttm:documentEbuttVersion>
                    </ebuttm:documentMetadata>
                </metadata>
                <styling>
                    <ebutts:style xml:id="defaultStyle" tts:fontFamily="proportionalSansSerif" tts:color="#FFFFFF"/>
                </styling>
            </head>
            <body><div>
                <p begin="00:00:01.000" end="00:00:02.000">Cue text</p>
            </div></body>
        </tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions[0].text, "Cue text")
    }

    func testMalformedTimestampThrows() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
            <p begin="not-a-time" end="00:00:02.000">Bad</p>
        </div></body></tt>
        """
        XCTAssertThrowsError(try CaptionParser.parseEBUTTD(xml)) { error in
            guard case CaptionParseError.malformedTimestamp = error else {
                return XCTFail("Expected malformedTimestamp, got \(error)")
            }
        }
    }

    func testFrameCountTimestampThrows() {
        // Specifically test that a file using iTT-style HH:MM:SS:FF timing
        // throws — that's the load-bearing strictness behavior. Without
        // this, an iTT file accidentally fed through the EBU-TT-D parser
        // would silently produce wrong timing.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
            <p begin="00:00:01:15" end="00:00:02:00">iTT-style timing</p>
        </div></body></tt>
        """
        XCTAssertThrowsError(try CaptionParser.parseEBUTTD(xml))
    }

    func testEmptyBodyProducesNoCaptions() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div></div></body></tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions.count, 0)
    }

    func testTrimsWhitespaceAroundCueText() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
            <p begin="00:00:01.000" end="00:00:02.000">
                Padded text
            </p>
        </div></body></tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions[0].text, "Padded text")
    }

    func testTTPrefixedAttributesAreRecognized() throws {
        // Some authoring tools emit `tt:begin` instead of bare `begin`.
        // The parser accepts both forms.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
            <p tt:begin="00:00:01.000" tt:end="00:00:02.000">Prefixed</p>
        </div></body></tt>
        """
        let captions = try CaptionParser.parseEBUTTD(xml)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions[0].text, "Prefixed")
    }
}
