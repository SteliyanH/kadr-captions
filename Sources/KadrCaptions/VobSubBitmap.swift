import Foundation
import CoreMedia
import CoreGraphics
import Kadr

// MARK: - Public value type

/// A single decoded subtitle bitmap from a VobSub `.sub` file. v0.7.
///
/// Pairs the cue timing (from `.idx` + the SPU's own control sequence) with a
/// rendered `CGImage` of the run-length-encoded subpicture pixels, palette-
/// expanded through the `.idx` palette and alpha-blended per the SPU's
/// 4-color alpha table.
///
/// `end` is computed from the SPU's `stop display` control command (the
/// `.idx` alone can't tell you how long a bitmap stays on screen — that's
/// encoded inside the SPU itself). For SPUs without an explicit stop command,
/// `end` falls back to the next `VobSubCue`'s start time (or `start + 5s`
/// for the trailing cue) so it always carries a sane duration.
public struct VobSubBitmap: Sendable {

    public let start: CMTime
    public let end: CMTime

    /// The rendered subpicture. Width / height match the SPU's display
    /// rectangle (`origin` field is dropped — callers position the bitmap on
    /// the timeline themselves using kadr's overlay layout).
    public let image: CGImage

    public init(start: CMTime, end: CMTime, image: CGImage) {
        self.start = start
        self.end = end
        self.image = image
    }
}

// MARK: - Public extraction surface

extension CaptionParser {

    /// Decode every cue in a `VobSubIndex` to a `VobSubBitmap` by reading the
    /// SPU packets at each cue's `fileOffset` out of the paired `.sub` blob.
    /// v0.7. Async only because real call sites read the `.sub` off disk —
    /// the decode itself is synchronous.
    ///
    /// Returns one `VobSubBitmap` per `VobSubCue`. Cues whose SPU fails to
    /// decode (truncated stream, unrecognized control command, palette out of
    /// range, etc.) are skipped silently — the typical failure mode is "the
    /// `.sub` was demuxed by a tool we don't model exactly," and dropping bad
    /// cues is better than throwing the whole batch out.
    ///
    /// - Parameters:
    ///   - idx: The `.idx` parsed via ``parseVobSubIndex(_:)``.
    ///   - sub: Raw bytes of the paired `.sub` file. Read once into memory;
    ///     real-world `.sub` files are a few megabytes at most.
    /// - Returns: The decoded bitmaps in `.idx` cue order. May be empty.
    public static func extractVobSubBitmaps(
        idx: VobSubIndex,
        sub: Data
    ) async -> [VobSubBitmap] {
        var output: [VobSubBitmap] = []
        output.reserveCapacity(idx.cues.count)

        for (i, cue) in idx.cues.enumerated() {
            guard let spu = assembleSPU(from: sub, startingAt: cue.fileOffset) else {
                continue
            }
            guard let parsed = parseSPU(spu) else { continue }
            guard let image = renderSPUImage(parsed: parsed, paletteHex: idx.paletteHex) else {
                continue
            }

            let fallbackEnd: CMTime
            if i + 1 < idx.cues.count {
                fallbackEnd = idx.cues[i + 1].start
            } else {
                fallbackEnd = cue.start + CMTime(value: 5000, timescale: 1000)
            }
            let end = spuEndTime(start: cue.start, parsed: parsed, fallback: fallbackEnd)

            output.append(VobSubBitmap(start: cue.start, end: end, image: image))
        }

        return output
    }
}

// MARK: - PES depacketizer

/// Internal: read one full SPU from the `.sub` blob starting at `offset`.
/// VobSub `.sub` files are MPEG-2 Program Stream containers — each SPU is
/// wrapped in one or more PES packets (private_stream_1, 0xBD) inside PS
/// packs (0xBA). This walker concatenates PES payloads until it has the SPU
/// size declared by the SPU's first two bytes.
///
/// Returns `nil` on truncation or sync-byte mismatch. Surfaced for testing.
internal func assembleSPU(from data: Data, startingAt offset: Int) -> Data? {
    guard offset >= 0, offset + 4 <= data.count else { return nil }

    let looksLikePS = data[offset] == 0x00 && data[offset + 1] == 0x00 && data[offset + 2] == 0x01
    if !looksLikePS {
        // Bare SPU at `offset`: first two bytes are the SPU size.
        let total = (Int(data[offset]) << 8) | Int(data[offset + 1])
        guard total >= 4, offset + total <= data.count else { return nil }
        return data.subdata(in: offset..<(offset + total))
    }

    var cursor = offset
    var collected = Data()
    var spuSize: Int?

    while cursor + 6 <= data.count {
        // Skip PS pack header (0x00 0x00 0x01 0xBA).
        if data[cursor] == 0x00, data[cursor + 1] == 0x00,
           data[cursor + 2] == 0x01, data[cursor + 3] == 0xBA {
            guard cursor + 14 <= data.count else { return nil }
            let stuffingLen = Int(data[cursor + 13] & 0x07)
            cursor += 14 + stuffingLen
            continue
        }

        // Expect a PES packet (private_stream_1 = 0xBD).
        guard data[cursor] == 0x00, data[cursor + 1] == 0x00,
              data[cursor + 2] == 0x01, data[cursor + 3] == 0xBD
        else { return nil }

        let packetLength = (Int(data[cursor + 4]) << 8) | Int(data[cursor + 5])
        let payloadStart = cursor + 6
        guard payloadStart + packetLength <= data.count else { return nil }
        let packetEnd = payloadStart + packetLength

        // PES extension header: flags (2) + header-data length (1), then
        // `headerDataLen` bytes. Skip a leading substream id byte (0x20-0x3F
        // for subpicture) that VobSub private streams use.
        var p = payloadStart
        guard p + 3 <= packetEnd else { return nil }
        let headerDataLen = Int(data[p + 2])
        p += 3 + headerDataLen
        guard p < packetEnd else { return nil }
        p += 1

        let chunk = data.subdata(in: p..<packetEnd)
        collected.append(chunk)

        if spuSize == nil, collected.count >= 2 {
            spuSize = (Int(collected[0]) << 8) | Int(collected[1])
        }

        cursor = packetEnd

        if let total = spuSize, collected.count >= total {
            return collected.prefix(total)
        }
    }

    return nil
}

// MARK: - SPU parser

/// Internal: parsed SPU layout — what the control sequence and pixel-data
/// offsets resolve to. Pure value type so the RLE / renderer steps can be
/// tested in isolation.
internal struct ParsedSPU {
    let bytes: Data
    let width: Int
    let height: Int
    let rleTopOffset: Int
    let rleBottomOffset: Int
    /// Indices into the `.idx` palette for the SPU's 4 logical colors. Order:
    /// background, pattern, emphasis1, emphasis2.
    let paletteIndices: [Int]   // 4 entries
    /// 4-bit alpha per logical color (0 = transparent, 15 = opaque).
    let alpha: [Int]            // 4 entries
    /// Display delay before showing (in 1/100 second ticks) and stop delay
    /// from the same SPU start. `nil` when the SPU omits a stop command.
    let startDelayCentis: Int
    let stopDelayCentis: Int?
}

internal func parseSPU(_ spu: Data) -> ParsedSPU? {
    guard spu.count >= 4 else { return nil }
    let size = (Int(spu[0]) << 8) | Int(spu[1])
    let dcsqtOffset = (Int(spu[2]) << 8) | Int(spu[3])
    guard size <= spu.count, dcsqtOffset < size, dcsqtOffset + 4 <= size else { return nil }

    var width = 0
    var height = 0
    var rleTop = 0
    var rleBottom = 0
    var paletteIndices = [0, 0, 0, 0]
    var alpha = [0, 0, 0, 0]
    var startDelay = 0
    var stopDelay: Int?

    var p = dcsqtOffset
    while p + 4 <= size {
        let dcsqStart = p
        let delay = (Int(spu[p]) << 8) | Int(spu[p + 1])
        let nextDCSQ = (Int(spu[p + 2]) << 8) | Int(spu[p + 3])
        p += 4

        var commandLoop = true
        while commandLoop, p < size {
            let cmd = spu[p]
            p += 1
            switch cmd {
            case 0x00:
                // force display — no extra bytes
                break
            case 0x01:
                startDelay = delay
            case 0x02:
                stopDelay = delay
            case 0x03:
                // palette indices: 2 bytes, 4 nibbles
                guard p + 2 <= size else { return nil }
                let b0 = Int(spu[p]); let b1 = Int(spu[p + 1])
                paletteIndices = [
                    (b0 >> 4) & 0x0F,
                    b0 & 0x0F,
                    (b1 >> 4) & 0x0F,
                    b1 & 0x0F,
                ]
                p += 2
            case 0x04:
                // alpha: 2 bytes, 4 nibbles
                guard p + 2 <= size else { return nil }
                let b0 = Int(spu[p]); let b1 = Int(spu[p + 1])
                alpha = [
                    (b0 >> 4) & 0x0F,
                    b0 & 0x0F,
                    (b1 >> 4) & 0x0F,
                    b1 & 0x0F,
                ]
                p += 2
            case 0x05:
                // display area: 6 bytes packed 12-bit each: x_start, x_end, y_start, y_end
                guard p + 6 <= size else { return nil }
                let xStart = (Int(spu[p]) << 4) | (Int(spu[p + 1]) >> 4)
                let xEnd = ((Int(spu[p + 1]) & 0x0F) << 8) | Int(spu[p + 2])
                let yStart = (Int(spu[p + 3]) << 4) | (Int(spu[p + 4]) >> 4)
                let yEnd = ((Int(spu[p + 4]) & 0x0F) << 8) | Int(spu[p + 5])
                width = max(0, xEnd - xStart + 1)
                height = max(0, yEnd - yStart + 1)
                p += 6
            case 0x06:
                // RLE offsets: 4 bytes (top_field, bottom_field)
                guard p + 4 <= size else { return nil }
                rleTop = (Int(spu[p]) << 8) | Int(spu[p + 1])
                rleBottom = (Int(spu[p + 2]) << 8) | Int(spu[p + 3])
                p += 4
            case 0xFF:
                commandLoop = false
            default:
                // Unknown command — bail; SPU is malformed or uses a feature we don't model.
                return nil
            }
        }

        // Stop if this DCSQ pointed at itself (end of chain), backwards, or out of range.
        if nextDCSQ == dcsqStart || nextDCSQ < dcsqtOffset || nextDCSQ >= size { break }
        p = nextDCSQ
    }

    guard width > 0, height > 0, rleTop < size, rleBottom <= size else { return nil }

    return ParsedSPU(
        bytes: spu,
        width: width,
        height: height,
        rleTopOffset: rleTop,
        rleBottomOffset: rleBottom,
        paletteIndices: paletteIndices,
        alpha: alpha,
        startDelayCentis: startDelay,
        stopDelayCentis: stopDelay
    )
}

// MARK: - RLE decoder

/// Internal: decode one field of the SPU's RLE pixel stream into a row-major
/// array of 2-bit color indices. Width is the SPU width; height is the per-
/// field height (full height halved, since the two fields interleave).
/// Returns `nil` on truncation. Pure — surfaced for tests.
internal func decodeVobSubRLE(
    data: Data,
    offset: Int,
    width: Int,
    height: Int
) -> [UInt8]? {
    guard offset >= 0, offset < data.count else { return nil }
    var pixels = [UInt8](repeating: 0, count: width * height)
    var byteCursor = offset
    var nibbleHigh = true   // true = next read is the high nibble of byteCursor

    func nextNibble() -> Int? {
        guard byteCursor < data.count else { return nil }
        let byte = Int(data[byteCursor])
        if nibbleHigh {
            nibbleHigh = false
            return (byte >> 4) & 0x0F
        } else {
            nibbleHigh = true
            byteCursor += 1
            return byte & 0x0F
        }
    }

    func alignToByte() {
        if !nibbleHigh {
            nibbleHigh = true
            byteCursor += 1
        }
    }

    for y in 0..<height {
        var x = 0
        while x < width {
            guard var code = nextNibble() else { return nil }
            // Cascade up to four nibbles until the code threshold is met.
            if code < 0x4 {
                guard let n2 = nextNibble() else { return nil }
                code = (code << 4) | n2
                if code < 0x10 {
                    guard let n3 = nextNibble() else { return nil }
                    code = (code << 4) | n3
                    if code < 0x40 {
                        guard let n4 = nextNibble() else { return nil }
                        code = (code << 4) | n4
                    }
                }
            }
            var len = code >> 2
            let color = UInt8(code & 0x03)
            if len == 0 {
                // Run-to-end-of-line.
                len = width - x
            }
            let runEnd = min(x + len, width)
            for px in x..<runEnd {
                pixels[y * width + px] = color
            }
            x = runEnd
        }
        // End of line: align to next byte.
        alignToByte()
    }

    return pixels
}

// MARK: - CGImage builder

/// Internal: render a parsed SPU through its palette + alpha to a RGBA
/// `CGImage`. Returns `nil` on malformed palette or RLE truncation.
internal func renderSPUImage(parsed: ParsedSPU, paletteHex: [String]?) -> CGImage? {
    let halfHeight = parsed.height / 2
    guard halfHeight > 0 else { return nil }
    guard let topField = decodeVobSubRLE(
        data: parsed.bytes,
        offset: parsed.rleTopOffset,
        width: parsed.width,
        height: halfHeight
    ) else { return nil }
    guard let bottomField = decodeVobSubRLE(
        data: parsed.bytes,
        offset: parsed.rleBottomOffset,
        width: parsed.width,
        height: parsed.height - halfHeight
    ) else { return nil }

    // Resolve each logical color (0-3) to RGBA via palette + alpha.
    let palette = paletteHex ?? Array(repeating: "000000", count: 16)
    var rgba: [(UInt8, UInt8, UInt8, UInt8)] = Array(repeating: (0, 0, 0, 0), count: 4)
    for logical in 0..<4 {
        let idx = parsed.paletteIndices[logical]
        let hex = (idx >= 0 && idx < palette.count) ? palette[idx] : "000000"
        let (r, g, b) = parseHexRGB(hex) ?? (0, 0, 0)
        let a = UInt8(min(255, parsed.alpha[logical] * 17))   // scale 0-15 → 0-255
        rgba[logical] = (r, g, b, a)
    }

    var pixelBytes = [UInt8](repeating: 0, count: parsed.width * parsed.height * 4)
    for y in 0..<parsed.height {
        let isTop = (y % 2 == 0)
        let fieldY = y / 2
        let field = isTop ? topField : bottomField
        for x in 0..<parsed.width {
            let logical = field[fieldY * parsed.width + x]
            let (r, g, b, a) = rgba[Int(logical)]
            let p = (y * parsed.width + x) * 4
            pixelBytes[p] = r
            pixelBytes[p + 1] = g
            pixelBytes[p + 2] = b
            pixelBytes[p + 3] = a
        }
    }

    let cs = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let provider = CGDataProvider(data: Data(pixelBytes) as CFData) else { return nil }
    return CGImage(
        width: parsed.width,
        height: parsed.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: parsed.width * 4,
        space: cs,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

// MARK: - Helpers

internal func parseHexRGB(_ hex: String) -> (UInt8, UInt8, UInt8)? {
    guard hex.count == 6 else { return nil }
    var value: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
    let v = UInt32(value & 0xFFFFFF)
    return (
        UInt8((v >> 16) & 0xFF),
        UInt8((v >> 8) & 0xFF),
        UInt8(v & 0xFF)
    )
}

internal func spuEndTime(start: CMTime, parsed: ParsedSPU, fallback: CMTime) -> CMTime {
    guard let stopCentis = parsed.stopDelayCentis else { return fallback }
    let delaySeconds = Double(stopCentis - parsed.startDelayCentis) / 100.0
    guard delaySeconds > 0 else { return fallback }
    return start + CMTime(seconds: delaySeconds, preferredTimescale: 1000)
}
