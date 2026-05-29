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

// MARK: - Caption split + frame-rate snap + array merge (v0.7.0)

extension Caption {

    /// Cleave a cue into two at `splitPoint` (an absolute timestamp). Both halves
    /// share the original text. `splitPoint` outside the cue's range collapses one
    /// half to a zero-duration cue at the appropriate boundary — the caller filters.
    ///
    /// Common use: a single cue spans a hard scene cut and the editor wants two
    /// independent cues with separate text. Caller then mutates each half's text
    /// downstream.
    ///
    /// ```swift
    /// let (first, second) = caption.split(at: midpoint)
    /// ```
    public func split(at splitPoint: CMTime) -> (Caption, Caption) {
        let start = timeRange.start
        let end = CMTimeAdd(start, timeRange.duration)

        if CMTimeCompare(splitPoint, start) <= 0 {
            // Cut at or before start: empty leading half, original trailing.
            let lead = Caption(text: text, timeRange: CMTimeRange(start: start, duration: .zero))
            return (lead, self)
        }
        if CMTimeCompare(splitPoint, end) >= 0 {
            // Cut at or after end: original leading, empty trailing at end.
            let trail = Caption(text: text, timeRange: CMTimeRange(start: end, duration: .zero))
            return (self, trail)
        }

        let leadDuration = CMTimeSubtract(splitPoint, start)
        let trailDuration = CMTimeSubtract(end, splitPoint)
        let lead = Caption(text: text, timeRange: CMTimeRange(start: start, duration: leadDuration))
        let trail = Caption(text: text, timeRange: CMTimeRange(start: splitPoint, duration: trailDuration))
        return (lead, trail)
    }

    /// Round the cue's `start` and `end` to the nearest frame boundary for the given
    /// frame rate (e.g., `23.976`, `24`, `25`, `29.97`, `30`, `60`). Duration is
    /// derived from the snapped boundaries — a 0.3-frame cue rounds to a 0-duration
    /// cue at the snapped start, and the caller filters.
    ///
    /// Non-positive or non-finite `frameRate` is a no-op (returns `self`); the
    /// editor's own validation surfaces the bad input rather than the bridge
    /// silently producing garbage timestamps.
    ///
    /// ```swift
    /// let aligned = caption.snappedToFrameRate(29.97)
    /// ```
    public func snappedToFrameRate(_ frameRate: Double) -> Caption {
        guard frameRate > 0, frameRate.isFinite else { return self }
        let snappedStart = snapToFrame(timeRange.start, frameRate: frameRate)
        let snappedEnd = snapToFrame(CMTimeAdd(timeRange.start, timeRange.duration), frameRate: frameRate)
        let duration = CMTimeMaximum(.zero, CMTimeSubtract(snappedEnd, snappedStart))
        return Caption(text: text, timeRange: CMTimeRange(start: snappedStart, duration: duration))
    }
}

extension Array where Element == Caption {

    /// Collapse adjacent cues whose inter-cue gap is at most `threshold`. Adjacent
    /// is defined as next-cue start minus current-cue end; cues overlap when this
    /// number is negative (still merged). Merged cues' text joins on `"\n"`; the
    /// merged range spans from the first cue's start to the last cue's end. Cues
    /// are assumed to be in chronological order — `merged(within:)` does not sort.
    ///
    /// Common use: a generated caption stream emits one short cue per word; merge
    /// adjacent words into displayable lines before export.
    ///
    /// ```swift
    /// let lines = words.merged(within: CMTime(seconds: 0.4, preferredTimescale: 600))
    /// ```
    public func merged(within threshold: CMTime) -> [Caption] {
        guard !isEmpty else { return [] }

        var output: [Caption] = []
        output.reserveCapacity(count)
        var current = self[0]

        for next in dropFirst() {
            let currentEnd = CMTimeAdd(current.timeRange.start, current.timeRange.duration)
            let gap = CMTimeSubtract(next.timeRange.start, currentEnd)
            if CMTimeCompare(gap, threshold) <= 0 {
                let mergedEnd = CMTimeMaximum(
                    currentEnd,
                    CMTimeAdd(next.timeRange.start, next.timeRange.duration)
                )
                let mergedDuration = CMTimeSubtract(mergedEnd, current.timeRange.start)
                let joinedText = current.text.isEmpty
                    ? next.text
                    : (next.text.isEmpty ? current.text : current.text + "\n" + next.text)
                current = Caption(
                    text: joinedText,
                    timeRange: CMTimeRange(start: current.timeRange.start, duration: mergedDuration)
                )
            } else {
                output.append(current)
                current = next
            }
        }
        output.append(current)
        return output
    }

    /// Apply ``Caption/snappedToFrameRate(_:)`` to every cue, preserving order.
    public func snappedToFrameRate(_ frameRate: Double) -> [Caption] {
        map { $0.snappedToFrameRate(frameRate) }
    }
}

// MARK: - Pure helpers

/// Round a `CMTime` to the nearest frame boundary at the given frame rate.
/// Pure — surfaced for tests. Frame rate must be positive and finite; callers
/// guard upstream.
internal func snapToFrame(_ time: CMTime, frameRate: Double) -> CMTime {
    let seconds = CMTimeGetSeconds(time)
    guard seconds.isFinite else { return time }
    let frameIndex = (seconds * frameRate).rounded()
    let snappedSeconds = frameIndex / frameRate
    return CMTime(seconds: snappedSeconds, preferredTimescale: time.timescale > 0 ? time.timescale : 1000)
}
