import XCTest
import CoreMedia
@testable import KadrCaptions

/// v0.6 Tier 2 — tests for WebVTT REGION block parsing + cue → region
/// resolution.
final class VTTRegionsTests: XCTestCase {

    // MARK: - REGION block parsing

    func testParseRegionBlockExtractsAllFields() {
        let region = CaptionParser.parseStyledVTTRegionBlock([
            "id:fred",
            "width:40%",
            "lines:3",
            "regionanchor:0%,100%",
            "viewportanchor:10%,90%",
            "scroll:up"
        ])
        XCTAssertEqual(region?.id, "fred")
        XCTAssertEqual(region?.widthPercent, 0.4)
        XCTAssertEqual(region?.lines, 3)
        XCTAssertEqual(region?.regionAnchorX, 0)
        XCTAssertEqual(region?.regionAnchorY, 1.0)
        XCTAssertEqual(region?.viewportAnchorX, 0.1)
        XCTAssertEqual(region?.viewportAnchorY, 0.9)
        XCTAssertEqual(region?.scroll, .up)
    }

    func testParseRegionBlockReturnsNilWithoutID() {
        // Regions without an id can't be referenced from a cue. The block
        // is meaningless — surface that by returning nil.
        let region = CaptionParser.parseStyledVTTRegionBlock([
            "width:30%",
            "lines:2"
        ])
        XCTAssertNil(region)
    }

    func testParseRegionBlockAppliesDefaultsForMissingFields() {
        let region = CaptionParser.parseStyledVTTRegionBlock(["id:only"])
        XCTAssertEqual(region?.widthPercent, 1.0)
        XCTAssertEqual(region?.lines, 3)
        XCTAssertEqual(region?.regionAnchorX, 0)
        XCTAssertEqual(region?.regionAnchorY, 1.0)
        XCTAssertEqual(region?.scroll, RegionScrollMode.none)
    }

    func testParseRegionBlockSilentlyIgnoresUnknownFields() {
        let region = CaptionParser.parseStyledVTTRegionBlock([
            "id:fred",
            "futureField:42",
            "width:50%"
        ])
        XCTAssertEqual(region?.id, "fred")
        XCTAssertEqual(region?.widthPercent, 0.5)
    }

    // MARK: - parseVTTRegionID

    func testParseVTTRegionIDExtractsFromSettings() {
        XCTAssertEqual(CaptionParser.parseVTTRegionID("region:fred align:center"), "fred")
        XCTAssertEqual(CaptionParser.parseVTTRegionID("align:start region:rolling-text"), "rolling-text")
    }

    func testParseVTTRegionIDReturnsNilWhenAbsent() {
        XCTAssertNil(CaptionParser.parseVTTRegionID("align:center line:50% position:30%"))
        XCTAssertNil(CaptionParser.parseVTTRegionID(""))
    }

    // MARK: - End-to-end parse + resolution

    func testStyledVTTAttachesRegionToReferencingCue() throws {
        let body = """
        WEBVTT

        REGION
        id:fred
        width:40%
        lines:3
        regionanchor:0%,100%
        viewportanchor:10%,90%
        scroll:up

        00:00:01.000 --> 00:00:05.000 region:fred align:center
        Hello world
        """
        let captions = try CaptionParser.parseStyledVTT(body)
        XCTAssertEqual(captions.count, 1)
        XCTAssertNotNil(captions[0].region)
        XCTAssertEqual(captions[0].region?.id, "fred")
        XCTAssertEqual(captions[0].region?.widthPercent, 0.4)
        XCTAssertEqual(captions[0].region?.scroll, .up)
    }

    func testStyledVTTLeavesRegionNilForCueWithoutReference() throws {
        let body = """
        WEBVTT

        REGION
        id:fred
        width:40%

        00:00:01.000 --> 00:00:05.000
        No region reference here
        """
        let captions = try CaptionParser.parseStyledVTT(body)
        XCTAssertNil(captions[0].region)
    }

    func testStyledVTTUnknownRegionReferenceResolvesToNil() throws {
        // A cue can reference a region that the file didn't declare —
        // tolerated (some authoring tools strip regions mid-pipeline).
        let body = """
        WEBVTT

        00:00:01.000 --> 00:00:05.000 region:ghost
        Hello
        """
        let captions = try CaptionParser.parseStyledVTT(body)
        XCTAssertNil(captions[0].region, "Ghost references resolve to nil, don't throw")
    }

    func testMultipleRegionsResolveIndependently() throws {
        let body = """
        WEBVTT

        REGION
        id:top
        regionanchor:50%,0%
        viewportanchor:50%,10%

        REGION
        id:bottom
        regionanchor:50%,100%
        viewportanchor:50%,90%

        00:00:01.000 --> 00:00:03.000 region:top
        Up there

        00:00:04.000 --> 00:00:06.000 region:bottom
        Down here
        """
        let captions = try CaptionParser.parseStyledVTT(body)
        XCTAssertEqual(captions.count, 2)
        XCTAssertEqual(captions[0].region?.id, "top")
        XCTAssertEqual(captions[1].region?.id, "bottom")
    }

    // MARK: - Plain parseVTT stays cleanly stripped

    func testPlainParseVTTIgnoresRegions() throws {
        // The plain parser doesn't surface regions — that path stays
        // unchanged from v0.5. The cue body still parses; the region
        // information is just absent.
        let body = """
        WEBVTT

        REGION
        id:fred
        width:40%

        00:00:01.000 --> 00:00:05.000 region:fred
        Hello
        """
        let captions = try CaptionParser.parseVTT(body)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions[0].text, "Hello")
        // Plain Caption has no region field — assertion is by structure
        // (caption parses cleanly without throwing).
    }
}
