import Foundation
import CoreMedia
import Kadr

// MARK: - Caption time transforms (v0.5.0)

extension Caption {

    /// Return a copy with the cue's `timeRange.start` shifted by `offset`. Negative
    /// offsets are clamped so `start` never goes below zero (the cue's duration is
    /// preserved by truncating the front instead).
    ///
    /// Common use: caption file generated from the original master shifted to align
    /// with a re-encoded export that prepends a logo / countdown.
    ///
    /// ```swift
    /// let cues = try await Caption.load(srt: url)
    /// let shifted = cues.shifted(by: CMTime(seconds: 3, preferredTimescale: 600))
    /// ```
    public func shifted(by offset: CMTime) -> Caption {
        let newStart = CMTimeAdd(timeRange.start, offset)
        if CMTimeCompare(newStart, .zero) < 0 {
            // Truncate the front: clamp start to zero, shrink duration accordingly.
            let lostFront = CMTimeSubtract(.zero, newStart)
            let newDuration = CMTimeMaximum(.zero, CMTimeSubtract(timeRange.duration, lostFront))
            return Caption(
                text: text,
                timeRange: CMTimeRange(start: .zero, duration: newDuration)
            )
        }
        return Caption(
            text: text,
            timeRange: CMTimeRange(start: newStart, duration: timeRange.duration)
        )
    }

    /// Return a copy with timestamps multiplied by `factor`. `1.0` is identity;
    /// `0.5` halves both `start` and `duration` (use after speeding the video up
    /// 2×); `2.0` doubles them.
    ///
    /// Negative or zero factors return a zero-range cue at zero — the editor's
    /// validity warning surfaces this rather than the bridge silently producing
    /// garbage.
    ///
    /// ```swift
    /// let halfSpeed = cues.scaled(by: 0.5)  // matches a 2× speed-ramp export
    /// ```
    public func scaled(by factor: Double) -> Caption {
        guard factor > 0, factor.isFinite else {
            return Caption(text: text, timeRange: CMTimeRange(start: .zero, duration: .zero))
        }
        let newStart = CMTimeMultiplyByFloat64(timeRange.start, multiplier: factor)
        let newDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: factor)
        return Caption(
            text: text,
            timeRange: CMTimeRange(start: newStart, duration: newDuration)
        )
    }
}

extension Array where Element == Caption {

    /// Apply ``Caption/shifted(by:)`` to every cue, preserving order.
    public func shifted(by offset: CMTime) -> [Caption] {
        map { $0.shifted(by: offset) }
    }

    /// Apply ``Caption/scaled(by:)`` to every cue, preserving order.
    public func scaled(by factor: Double) -> [Caption] {
        map { $0.scaled(by: factor) }
    }
}
