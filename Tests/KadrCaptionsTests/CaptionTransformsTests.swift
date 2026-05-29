import XCTest
import CoreMedia
import Kadr
@testable import KadrCaptions

final class CaptionTransformsTests: XCTestCase {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func cue(_ start: Double, _ end: Double, _ text: String = "") -> Caption {
        Caption(
            text: text,
            timeRange: CMTimeRange(
                start: cmt(start),
                duration: cmt(end - start)
            )
        )
    }

    // MARK: - shifted(by:)

    func testShiftPositiveMovesStart() {
        let original = cue(2.0, 4.0, "hi")
        let shifted = original.shifted(by: cmt(1.5))
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.start), 3.5, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.duration), 2.0, accuracy: 0.0001)
        XCTAssertEqual(shifted.text, "hi")
    }

    func testShiftNegativeWithinRangeMovesBack() {
        let original = cue(5.0, 7.0)
        let shifted = original.shifted(by: cmt(-2.0))
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.start), 3.0, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.duration), 2.0, accuracy: 0.0001)
    }

    func testShiftNegativePastZeroTruncatesFront() {
        // Original 1...3 shifted by -2 → start clamps to 0, duration shrinks by 1
        // (the lost front).
        let original = cue(1.0, 3.0)
        let shifted = original.shifted(by: cmt(-2.0))
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.start), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.duration), 1.0, accuracy: 0.0001)
    }

    func testShiftNegativePastEndCollapsesToZero() {
        // Original 1...3 shifted by -10 → start clamps to 0, duration collapses to 0
        // (entire cue lost off the front).
        let original = cue(1.0, 3.0)
        let shifted = original.shifted(by: cmt(-10.0))
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.start), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(shifted.timeRange.duration), 0.0, accuracy: 0.0001)
    }

    func testShiftPreservesText() {
        let original = cue(0.0, 1.0, "Multi\nline cue")
        XCTAssertEqual(original.shifted(by: cmt(5.0)).text, "Multi\nline cue")
    }

    // MARK: - scaled(by:)

    func testScaleHalvesBothStartAndDuration() {
        let original = cue(2.0, 4.0)
        let scaled = original.scaled(by: 0.5)
        XCTAssertEqual(CMTimeGetSeconds(scaled.timeRange.start), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(scaled.timeRange.duration), 1.0, accuracy: 0.0001)
    }

    func testScaleDoublesBothStartAndDuration() {
        let original = cue(1.5, 2.5)
        let scaled = original.scaled(by: 2.0)
        XCTAssertEqual(CMTimeGetSeconds(scaled.timeRange.start), 3.0, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(scaled.timeRange.duration), 2.0, accuracy: 0.0001)
    }

    func testScaleByOneIsIdentity() {
        let original = cue(2.5, 5.5, "x")
        let scaled = original.scaled(by: 1.0)
        XCTAssertEqual(CMTimeGetSeconds(scaled.timeRange.start), 2.5, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(scaled.timeRange.duration), 3.0, accuracy: 0.0001)
    }

    func testScaleByZeroCollapsesToZeroRange() {
        // Defensive — engine would reject but better to surface here visibly.
        let original = cue(2.0, 5.0)
        let scaled = original.scaled(by: 0.0)
        XCTAssertEqual(scaled.timeRange.start, .zero)
        XCTAssertEqual(scaled.timeRange.duration, .zero)
    }

    func testScaleNegativeCollapsesToZeroRange() {
        let original = cue(2.0, 5.0)
        let scaled = original.scaled(by: -1.0)
        XCTAssertEqual(scaled.timeRange.start, .zero)
        XCTAssertEqual(scaled.timeRange.duration, .zero)
    }

    // MARK: - Array sugar

    func testArrayShiftAppliesToEveryCue() {
        let cues = [cue(0.0, 1.0, "a"), cue(2.0, 3.0, "b")]
        let shifted = cues.shifted(by: cmt(1.0))
        XCTAssertEqual(shifted.map { CMTimeGetSeconds($0.timeRange.start) }, [1.0, 3.0])
    }

    func testArrayScaleAppliesToEveryCue() {
        let cues = [cue(0.0, 2.0, "a"), cue(2.0, 4.0, "b")]
        let scaled = cues.scaled(by: 0.5)
        XCTAssertEqual(scaled.map { CMTimeGetSeconds($0.timeRange.start) }, [0.0, 1.0])
        XCTAssertEqual(scaled.map { CMTimeGetSeconds($0.timeRange.duration) }, [1.0, 1.0])
    }

    func testArrayPreservesOrder() {
        let cues = [cue(5.0, 6.0, "first"), cue(1.0, 2.0, "second")]
        // Shifting / scaling never reorders — sorting is the consumer's job.
        XCTAssertEqual(cues.shifted(by: cmt(0)).map(\.text), ["first", "second"])
    }

    // MARK: - split(at:) — v0.7

    func testSplitAtMidpointReturnsTwoEqualHalves() {
        let c = cue(2.0, 6.0, "hi")
        let (a, b) = c.split(at: cmt(4.0))
        XCTAssertEqual(CMTimeGetSeconds(a.timeRange.start), 2.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(a.timeRange.duration), 2.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(b.timeRange.start), 4.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(b.timeRange.duration), 2.0, accuracy: 0.001)
        XCTAssertEqual(a.text, "hi")
        XCTAssertEqual(b.text, "hi")
    }

    func testSplitBeforeStartCollapsesLeadingHalf() {
        let c = cue(2.0, 6.0, "hi")
        let (a, b) = c.split(at: cmt(1.0))
        XCTAssertEqual(CMTimeGetSeconds(a.timeRange.duration), 0.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(a.timeRange.start), 2.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(b.timeRange.start), 2.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(b.timeRange.duration), 4.0, accuracy: 0.001)
    }

    func testSplitAfterEndCollapsesTrailingHalf() {
        let c = cue(2.0, 6.0, "hi")
        let (a, b) = c.split(at: cmt(10.0))
        XCTAssertEqual(CMTimeGetSeconds(a.timeRange.duration), 4.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(b.timeRange.start), 6.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(b.timeRange.duration), 0.0, accuracy: 0.001)
    }

    // MARK: - snappedToFrameRate(_:) — v0.7

    func testSnapAt30FPSRoundsToNearestFrame() {
        // 30 fps → 1 frame = 1/30 ≈ 0.0333s. 2.01s rounds to 2.0; 2.02s rounds to 2.0333.
        let c = cue(2.01, 3.02, "hi")
        let snapped = c.snappedToFrameRate(30.0)
        XCTAssertEqual(CMTimeGetSeconds(snapped.timeRange.start), 2.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(snapped.timeRange.start + snapped.timeRange.duration), 3.0333, accuracy: 0.001)
    }

    func testSnapAt2398FPSHonorsNonIntegerRate() {
        // 23.976 fps → 1 frame ≈ 0.04171s. 0.05 ≈ 1.2 frames → rounds to frame 1.
        let c = cue(0.05, 1.0, "hi")
        let snapped = c.snappedToFrameRate(23.976)
        XCTAssertEqual(CMTimeGetSeconds(snapped.timeRange.start), 0.0417, accuracy: 0.001)
    }

    func testSnapInvalidFrameRateIsNoOp() {
        let c = cue(2.123, 4.567, "hi")
        let snappedZero = c.snappedToFrameRate(0)
        XCTAssertEqual(snappedZero.timeRange.start, c.timeRange.start)
        let snappedNegative = c.snappedToFrameRate(-30)
        XCTAssertEqual(snappedNegative.timeRange.start, c.timeRange.start)
    }

    func testArraySnapAppliesToEveryCue() {
        let cues = [cue(0.01, 1.02), cue(2.04, 3.07)]
        let snapped = cues.snappedToFrameRate(30.0)
        XCTAssertEqual(snapped.count, 2)
        XCTAssertEqual(CMTimeGetSeconds(snapped[0].timeRange.start), 0.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(snapped[1].timeRange.start), 2.0333, accuracy: 0.001)
    }

    // MARK: - Array.merged(within:) — v0.7

    func testMergeCollapsesAdjacentCuesWithinThreshold() {
        let cues = [
            cue(0.0, 1.0, "hello"),
            cue(1.2, 2.0, "world"),   // gap 0.2s
            cue(5.0, 6.0, "later")
        ]
        let merged = cues.merged(within: cmt(0.3))
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].text, "hello\nworld")
        XCTAssertEqual(CMTimeGetSeconds(merged[0].timeRange.start), 0.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(merged[0].timeRange.duration), 2.0, accuracy: 0.001)
        XCTAssertEqual(merged[1].text, "later")
    }

    func testMergeLeavesCuesAboveThresholdUntouched() {
        let cues = [cue(0.0, 1.0, "a"), cue(1.5, 2.5, "b")]
        let merged = cues.merged(within: cmt(0.1))
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.text), ["a", "b"])
    }

    func testMergeHandlesOverlappingCues() {
        let cues = [cue(0.0, 2.0, "a"), cue(1.0, 3.0, "b")]
        let merged = cues.merged(within: cmt(0))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "a\nb")
        XCTAssertEqual(CMTimeGetSeconds(merged[0].timeRange.duration), 3.0, accuracy: 0.001)
    }

    func testMergeEmptyArrayReturnsEmpty() {
        let merged: [Caption] = [].merged(within: cmt(1))
        XCTAssertTrue(merged.isEmpty)
    }

    func testMergeSingleCuePassesThrough() {
        let cues = [cue(0.0, 1.0, "alone")]
        let merged = cues.merged(within: cmt(1))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "alone")
    }

    func testMergeOmitsEmptyTextSeparator() {
        let cues = [cue(0.0, 1.0, ""), cue(1.0, 2.0, "second")]
        let merged = cues.merged(within: cmt(0.1))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "second")
    }

    // MARK: - snapToFrame helper

    func testSnapToFrameRoundsHalfFrameUp() {
        // 30 fps, time = 0.0167 (half a frame) → 1/30 = 0.0333
        let snapped = snapToFrame(CMTime(seconds: 0.0167, preferredTimescale: 600), frameRate: 30)
        XCTAssertEqual(CMTimeGetSeconds(snapped), 0.0333, accuracy: 0.001)
    }
}
