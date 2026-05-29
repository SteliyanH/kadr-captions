import XCTest
import CoreMedia
import CoreGraphics
@testable import KadrCaptions

/// v0.7 Tier 1 — tests for the `.sub` VobSub bitmap decoder.
///
/// Every fixture is hand-synthesized inline so the test surface stays
/// portable and the wire format is documented alongside each assertion.
/// `parseHexRGB`, `decodeVobSubRLE`, `parseSPU`, and `renderSPUImage` are
/// exercised in isolation; the public `extractVobSubBitmaps(idx:sub:)` path
/// is exercised end-to-end against a bare-SPU `.sub` (no PES wrapper) and
/// against a minimal PES-wrapped `.sub`.
final class VobSubBitmapTests: XCTestCase {

    // MARK: - parseHexRGB

    func testParseHexRGBRedChannel() {
        let parsed = parseHexRGB("ff0000")
        XCTAssertEqual(parsed?.0, 255)
        XCTAssertEqual(parsed?.1, 0)
        XCTAssertEqual(parsed?.2, 0)
    }

    func testParseHexRGBRejectsShortInput() {
        XCTAssertNil(parseHexRGB("fff"))
    }

    func testParseHexRGBRejectsNonHex() {
        XCTAssertNil(parseHexRGB("zz0000"))
    }

    // MARK: - decodeVobSubRLE

    /// `0x11` = nibble 0x1 (cascade) + 0x1 → code 0x11; len = 0x11 >> 2 = 4,
    /// color = 1. Fills the entire width-4 line with color 1.
    func testRLESingleEightBitCodeFillsLine() {
        let pixels = decodeVobSubRLE(data: Data([0x11]), offset: 0, width: 4, height: 1)
        XCTAssertEqual(pixels, [1, 1, 1, 1])
    }

    /// Four 4-bit codes (`0x44 0x44`): each is len=1, color=0; four pixels.
    func testRLEFourBitCodesFillLine() {
        let pixels = decodeVobSubRLE(data: Data([0x44, 0x44]), offset: 0, width: 4, height: 1)
        XCTAssertEqual(pixels, [0, 0, 0, 0])
    }

    /// `0x00 0x01` cascades through all four nibble levels to code 0x0001.
    /// len = 0 (run-to-end-of-line) with color = 1. Fills width-4 with 1.
    func testRLERunToEndOfLine() {
        let pixels = decodeVobSubRLE(data: Data([0x00, 0x01]), offset: 0, width: 4, height: 1)
        XCTAssertEqual(pixels, [1, 1, 1, 1])
    }

    func testRLEReturnsNilOnTruncation() {
        // Need 2 nibbles to decode but only 1 byte's worth of data — first
        // nibble 0x1 forces cascade, but there's no second nibble after the
        // single byte is consumed (decoder reads high+low of one byte = 2
        // nibbles; on a 4-px line with code 0x11 we'd succeed, so use 0x10
        // which is a valid 8-bit code but len=4 fills 4 px, leaving height
        // 2 short).
        let pixels = decodeVobSubRLE(data: Data([0x11]), offset: 0, width: 4, height: 2)
        XCTAssertNil(pixels, "decoder should fail when stream ends mid-image")
    }

    // MARK: - parseSPU + end-to-end via extractVobSubBitmaps

    /// Minimal SPU: width=4, height=2, all pixels color 1 (opaque red via the
    /// `.idx` palette). Two DCSQs — first sets palette / alpha / rect / RLE
    /// offsets / start-display, second sets stop-display at delay 50 (= 0.5s).
    private func synthesizeMinimalSPU() -> Data {
        Data([
            0x00, 0x24,           // SPU size = 36
            0x00, 0x06,           // DCSQT offset = 6
            0x11,                 // RLE top  (len=4, color=1)
            0x11,                 // RLE bottom (len=4, color=1)

            // DCSQ #1 @ offset 6
            0x00, 0x00,           // delay = 0
            0x00, 0x1E,           // next DCSQ = 30
            0x03, 0x01, 0x23,     // palette: logical 0→1, 1→0, 2→3, 3→2 (high/low of each byte)
            0x04, 0xFF, 0xFF,     // alpha: opaque for all 4 logical colors
            0x05, 0x00, 0x00, 0x03, 0x00, 0x00, 0x01,  // rect: xs=0, xe=3, ys=0, ye=1
            0x06, 0x00, 0x04, 0x00, 0x05,              // RLE offsets: top=4, bottom=5
            0x01,                 // start display
            0xFF,                 // end DCSQ #1

            // DCSQ #2 @ offset 30
            0x00, 0x32,           // delay = 50 (0.5s)
            0x00, 0x1E,           // next DCSQ = self → end of chain
            0x02,                 // stop display
            0xFF                  // end DCSQ #2
        ])
    }

    func testParseSPURecoversRectAndOffsets() {
        let spu = synthesizeMinimalSPU()
        let parsed = parseSPU(spu)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.width, 4)
        XCTAssertEqual(parsed?.height, 2)
        XCTAssertEqual(parsed?.rleTopOffset, 4)
        XCTAssertEqual(parsed?.rleBottomOffset, 5)
        XCTAssertEqual(parsed?.paletteIndices, [0, 1, 2, 3])
        XCTAssertEqual(parsed?.alpha, [15, 15, 15, 15])
        XCTAssertEqual(parsed?.startDelayCentis, 0)
        XCTAssertEqual(parsed?.stopDelayCentis, 50)
    }

    func testRenderSPUImageDimensions() {
        let spu = synthesizeMinimalSPU()
        guard let parsed = parseSPU(spu) else {
            return XCTFail("parseSPU returned nil")
        }
        let palette = Array(repeating: "ff0000", count: 16)
        let image = renderSPUImage(parsed: parsed, paletteHex: palette)
        XCTAssertEqual(image?.width, 4)
        XCTAssertEqual(image?.height, 2)
    }

    func testExtractVobSubBitmapsBareSPUFallback() async {
        // `.sub` is just the SPU bytes with no PES wrapper; `assembleSPU`'s
        // bare-SPU fallback should pick it up.
        let spu = synthesizeMinimalSPU()
        let idx = VobSubIndex(
            language: "en",
            paletteHex: Array(repeating: "ff0000", count: 16),
            cues: [VobSubCue(start: CMTime(value: 1000, timescale: 1000), fileOffset: 0)]
        )

        let bitmaps = await CaptionParser.extractVobSubBitmaps(idx: idx, sub: spu)
        XCTAssertEqual(bitmaps.count, 1)
        XCTAssertEqual(bitmaps.first?.image.width, 4)
        XCTAssertEqual(bitmaps.first?.image.height, 2)
        XCTAssertEqual(CMTimeGetSeconds(bitmaps.first?.start ?? .zero), 1.0, accuracy: 0.001)
        // SPU stop delay 50 centis = 0.5s after start.
        XCTAssertEqual(CMTimeGetSeconds(bitmaps.first?.end ?? .zero), 1.5, accuracy: 0.01)
    }

    func testExtractVobSubBitmapsPESWrapped() async {
        // Wrap the SPU inside one PS pack (0xBA, 14 bytes + no stuffing) and
        // one PES packet (private_stream_1 = 0xBD) with a minimal PES header
        // (flags 0x80 0x00 + 0-byte header data) + substream id 0x20.
        let spu = synthesizeMinimalSPU()
        let pesPayloadHeader: [UInt8] = [
            0x80, 0x00, 0x00,     // PES flags + header data length 0
            0x20                  // substream id (subpicture)
        ]
        let pesPayloadLength = pesPayloadHeader.count + spu.count
        let pesHeader: [UInt8] = [
            0x00, 0x00, 0x01, 0xBD,
            UInt8((pesPayloadLength >> 8) & 0xFF),
            UInt8(pesPayloadLength & 0xFF)
        ]
        let packHeader: [UInt8] = [
            0x00, 0x00, 0x01, 0xBA,
            0x44, 0x00, 0x04, 0x00, 0x04, 0x01, 0x00, 0x01,
            0xCC, 0xF8,           // bitrate + stuffing-length nibble (low 3 bits = 0)
        ]

        var sub = Data()
        sub.append(contentsOf: packHeader)
        sub.append(contentsOf: pesHeader)
        sub.append(contentsOf: pesPayloadHeader)
        sub.append(spu)

        let idx = VobSubIndex(
            language: "en",
            paletteHex: Array(repeating: "00ff00", count: 16),
            cues: [VobSubCue(start: CMTime(value: 2000, timescale: 1000), fileOffset: 0)]
        )

        let bitmaps = await CaptionParser.extractVobSubBitmaps(idx: idx, sub: sub)
        XCTAssertEqual(bitmaps.count, 1)
        XCTAssertEqual(bitmaps.first?.image.width, 4)
    }

    func testExtractVobSubBitmapsDropsBadCues() async {
        // One valid SPU at offset 0; a second cue points past the end of
        // data (assembleSPU returns nil) and is silently dropped.
        let spu = synthesizeMinimalSPU()
        let idx = VobSubIndex(
            language: "en",
            paletteHex: Array(repeating: "ffffff", count: 16),
            cues: [
                VobSubCue(start: CMTime(value: 0, timescale: 1000), fileOffset: 0),
                VobSubCue(start: CMTime(value: 5000, timescale: 1000), fileOffset: 9999)
            ]
        )

        let bitmaps = await CaptionParser.extractVobSubBitmaps(idx: idx, sub: spu)
        XCTAssertEqual(bitmaps.count, 1)
    }

    // MARK: - spuEndTime fallback

    func testSPUEndTimeUsesFallbackWithoutStopDelay() {
        let parsed = ParsedSPU(
            bytes: Data(),
            width: 1, height: 1,
            rleTopOffset: 0, rleBottomOffset: 0,
            paletteIndices: [0, 0, 0, 0],
            alpha: [0, 0, 0, 0],
            startDelayCentis: 0,
            stopDelayCentis: nil
        )
        let fallback = CMTime(value: 3000, timescale: 1000)
        let end = spuEndTime(start: .zero, parsed: parsed, fallback: fallback)
        XCTAssertEqual(end, fallback)
    }
}
