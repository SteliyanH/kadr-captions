import Foundation

/// A WebVTT REGION block — positioning + scrolling metadata for one or more
/// styled cues. v0.6.
///
/// Modern VTT files (browser caption editors, broadcast streams) carry
/// REGION blocks above the cue list, each declaring a named viewport
/// rectangle. Cues reference a region by id via their `region:NAME` setting
/// and inherit its layout. v0.6 surfaces this through
/// ``StyledCaption/region`` — the plain ``CaptionParser/parseVTT(_:)`` path
/// stays cleanly stripped (regions are a styled-only concern), and the
/// styled parser resolves cue → region by name.
///
/// **What this struct DOESN'T do.** Render. The region carries enough
/// metadata for a downstream renderer (kadr-ui's overlay layout, or a
/// custom view) to position the cue correctly, but the styled-caption
/// bridge in this package still produces a single `TextOverlay` per cue
/// — region anchoring is consumer responsibility. A future cycle can wire
/// regions into `StyledCaption.toTextOverlay(...)` when the kadr-ui
/// surface is ready to consume them.
public struct CaptionRegion: Sendable, Equatable {

    /// REGION block id. Cues reference it via `region:NAME` in their cue
    /// settings string. Empty when the block omits an id (defensive — real
    /// VTT files always declare one).
    public let id: String

    /// Region width as a fraction of the viewport (`0...1`). VTT's
    /// `width:NN%` setting; defaults to `1.0` (full viewport width) when
    /// the block omits it.
    public let widthPercent: Double

    /// Maximum lines visible in the region before older ones scroll off
    /// (when `scroll == .up`). VTT's `lines:N` setting; defaults to `3`.
    public let lines: Int

    /// Anchor point inside the region itself, in `0...1` per axis. VTT's
    /// `regionanchor:Nx%,Ny%` setting. Defaults to `(0, 100%)` (bottom-left).
    public let regionAnchorX: Double
    public let regionAnchorY: Double

    /// Anchor point on the viewport where the region's `regionAnchor`
    /// lands. VTT's `viewportanchor:Nx%,Ny%` setting. Defaults to
    /// `(0, 100%)`.
    public let viewportAnchorX: Double
    public let viewportAnchorY: Double

    /// Scroll behavior when text exceeds `lines`. VTT defines only `.up`;
    /// absence of the setting means `.none` (cues overflow without
    /// scrolling). Future spec extensions might add more cases — keeping
    /// the enum non-frozen.
    public let scroll: RegionScrollMode

    public init(
        id: String,
        widthPercent: Double = 1.0,
        lines: Int = 3,
        regionAnchorX: Double = 0,
        regionAnchorY: Double = 1.0,
        viewportAnchorX: Double = 0,
        viewportAnchorY: Double = 1.0,
        scroll: RegionScrollMode = .none
    ) {
        self.id = id
        self.widthPercent = widthPercent
        self.lines = lines
        self.regionAnchorX = regionAnchorX
        self.regionAnchorY = regionAnchorY
        self.viewportAnchorX = viewportAnchorX
        self.viewportAnchorY = viewportAnchorY
        self.scroll = scroll
    }
}

/// WebVTT REGION block scroll behavior. v0.6.
///
/// VTT spec defines only `.up` (cues scroll upward when the line count
/// exceeds the region's `lines:` setting); absence of the `scroll:`
/// directive means cues simply overflow.
public enum RegionScrollMode: String, Sendable, Equatable {
    case none
    case up
}
