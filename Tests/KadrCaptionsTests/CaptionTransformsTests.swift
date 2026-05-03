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
}
