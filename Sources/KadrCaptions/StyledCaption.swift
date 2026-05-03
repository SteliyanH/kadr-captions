import Foundation
import CoreMedia

/// A caption cue with preserved styling. Produced by ``CaptionParser/parseStyledVTT(_:)``
/// (or hand-built) and rendered as a styled `Kadr.TextOverlay` via
/// ``StyledCaption/toTextOverlay(baseStyle:animation:)``.
///
/// Plain-text consumption (`Video.captions(_:)` → `AVMetadataItem`) keeps the v0.1
/// `Caption` type. `StyledCaption` is a parallel surface for visual rendering — the
/// two coexist; converting between them is a `.text` / `.timeRange` access away.
public struct StyledCaption: Sendable, Equatable {

    /// Plain caption text, with all `<...>` tags stripped. Equivalent to what
    /// ``CaptionParser/parseVTT(_:)`` produces for the same cue.
    public let text: String

    /// Composition-time range during which the cue is visible.
    public let timeRange: CMTimeRange

    /// Horizontal alignment within the cue's layout box. Maps to
    /// `Kadr.TextStyle.Alignment` at bridge time. Default ``StyledCaptionAlignment/center``.
    public let alignment: StyledCaptionAlignment

    /// Vertical placement on the render canvas (WebVTT's `line:` setting). Default
    /// ``StyledCaptionLine/auto`` — rendered at the bottom of the canvas.
    public let line: StyledCaptionLine

    /// Horizontal position in `0...1` (WebVTT's `position:` setting, divided by 100).
    /// Default `0.5` (centered).
    public let position: Double

    /// `true` if any `<b>` tag is present anywhere in the cue's text. v0.3 collapses
    /// mixed inline styling to a single per-cue flag — multi-run text is deferred.
    public let isBold: Bool

    /// `true` if any `<i>` tag is present anywhere in the cue's text.
    public let isItalic: Bool

    /// `true` if any `<u>` tag is present anywhere in the cue's text. Recorded for
    /// forward compatibility; not yet rendered (kadr `TextStyle` has no underline
    /// field as of kadr 0.9).
    public let isUnderlined: Bool

    /// Speaker name extracted from a `<v Speaker>` tag, if present.
    public let speaker: String?

    /// Classnames from `<c.foo.bar>` tags, accumulated across the cue. Recorded for
    /// forward compatibility with the v0.3.x `<STYLE>`-block parser.
    public let classes: [String]

    /// Foreground color as a `#RRGGBB` (or `#RRGGBBAA`) hex string, or `nil` to
    /// inherit `baseStyle.color` at bridge time. ASS / SSA fill-color overrides
    /// (`{\1c&HBBGGRR&}`) round-trip into this field; the
    /// ``StyledCaption/toTextOverlay(baseStyle:animation:)`` bridge applies it
    /// to the resulting `Kadr.TextStyle`. Added in v0.5.0.
    public let color: String?

    public init(
        text: String,
        timeRange: CMTimeRange,
        alignment: StyledCaptionAlignment = .center,
        line: StyledCaptionLine = .auto,
        position: Double = 0.5,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        speaker: String? = nil,
        classes: [String] = [],
        color: String? = nil
    ) {
        self.text = text
        self.timeRange = timeRange
        self.alignment = alignment
        self.line = line
        self.position = position
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.speaker = speaker
        self.classes = classes
        self.color = color
    }
}

/// Horizontal alignment of a styled caption's text. Mirrors WebVTT's `align:` setting.
public enum StyledCaptionAlignment: Sendable, Equatable {
    case start
    case center
    case end
}

/// Vertical placement of a styled caption on the render canvas. Mirrors WebVTT's
/// `line:` setting.
public enum StyledCaptionLine: Sendable, Equatable {
    /// Default WebVTT placement — bottom of the canvas.
    case auto
    case top
    case bottom
    /// Explicit vertical position in `0...100` (percent of canvas height from top).
    case percent(Double)
}
