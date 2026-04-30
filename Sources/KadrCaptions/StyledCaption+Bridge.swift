import Foundation
import CoreMedia
import Kadr

extension StyledCaption {

    /// Build a `Kadr.TextOverlay` rendering this caption.
    ///
    /// `baseStyle` provides the font / color / weight defaults; the cue's own bold /
    /// italic flags override the base where present (`isBold` → `Weight.bold`,
    /// `isItalic` → `fontName = "Helvetica-Oblique"`). The cue's alignment overrides
    /// `baseStyle.alignment`. Position / anchor follow WebVTT semantics: the
    /// alignment point of the text sits at `(position, line)` on the canvas.
    ///
    /// `visibilityRange` is set from `timeRange` so the overlay only draws while the
    /// caption should be on screen. If `animation` is non-nil it's attached
    /// unchanged.
    public func toTextOverlay(
        baseStyle: TextStyle = .default,
        animation: (any TextAnimation)? = nil
    ) -> TextOverlay {
        let style = StyledCaption.applyStyling(base: baseStyle, isBold: isBold, isItalic: isItalic, alignment: alignment)
        let position = StyledCaption.overlayPosition(line: line, position: self.position)
        let anchor = StyledCaption.overlayAnchor(line: line, alignment: alignment)

        var overlay = TextOverlay(text, style: style)
            .position(position)
            .anchor(anchor)
            .visible(during: timeRange)
        if let animation {
            overlay = overlay.animation(animation)
        }
        return overlay
    }

    // MARK: - Pure mapping helpers (exposed for tests)

    /// Compose the final `TextStyle` from a base + the cue's bold / italic /
    /// alignment overrides. Pure.
    public static func applyStyling(
        base: TextStyle,
        isBold: Bool,
        isItalic: Bool,
        alignment: StyledCaptionAlignment
    ) -> TextStyle {
        var style = base
        style.alignment = mapAlignment(alignment)
        if isBold {
            style.weight = .bold
        }
        if isItalic {
            // Hardcoded for portability across Apple platforms. Documented limitation:
            // a custom non-italic font in `baseStyle.fontName` is overridden when the
            // cue requests italic.
            style.fontName = "Helvetica-Oblique"
        }
        return style
    }

    /// Map ``StyledCaptionAlignment`` to `Kadr.TextStyle.Alignment`. Pure.
    public static func mapAlignment(_ alignment: StyledCaptionAlignment) -> TextStyle.Alignment {
        switch alignment {
        case .start:  return .leading
        case .center: return .center
        case .end:    return .trailing
        }
    }

    /// Resolve the overlay's `Kadr.Position` from the cue's line + horizontal
    /// position. The y-coordinate maps WebVTT line semantics:
    /// - `.auto` / `.bottom` → `y = 0.92`
    /// - `.top` → `y = 0.08`
    /// - `.percent(p)` → `y = p / 100`
    /// Pure.
    public static func overlayPosition(line: StyledCaptionLine, position: Double) -> Position {
        let y: Double
        switch line {
        case .auto, .bottom: y = 0.92
        case .top:           y = 0.08
        case .percent(let p): y = max(0, min(1, p / 100.0))
        }
        return .normalized(x: position, y: y)
    }

    /// Resolve the overlay's `Kadr.Anchor` from the cue's line + alignment. Anchor
    /// sticks the appropriate corner / edge of the text at `overlayPosition(...)`.
    /// Pure.
    public static func overlayAnchor(
        line: StyledCaptionLine,
        alignment: StyledCaptionAlignment
    ) -> Kadr.Anchor {
        let isTop: Bool
        switch line {
        case .top: isTop = true
        case .auto, .bottom: isTop = false
        case .percent(let p): isTop = p < 50
        }

        switch (isTop, alignment) {
        case (true,  .start):  return .topLeft
        case (true,  .center): return .top
        case (true,  .end):    return .topRight
        case (false, .start):  return .bottomLeft
        case (false, .center): return .bottom
        case (false, .end):    return .bottomRight
        }
    }
}

// MARK: - Video.styledCaptions

extension Video {

    /// Overlay every styled caption onto the composition. Each becomes a
    /// `TextOverlay` with its own `visibilityRange` (driven by the cue's
    /// `timeRange`) and the supplied base style / animation.
    ///
    /// ```swift
    /// let cues = try await Caption.loadStyled(vtt: vttURL)
    /// let video = Video {
    ///     VideoClip(url: footage)
    /// }
    /// .styledCaptions(cues, animation: .fadeIn(duration: 0.3))
    /// ```
    ///
    /// Multiple `.styledCaptions(_:)` calls accumulate.
    public func styledCaptions(
        _ captions: [StyledCaption],
        baseStyle: TextStyle = .default,
        animation: (any TextAnimation)? = nil
    ) -> Video {
        var v = self
        for cue in captions {
            v = v.overlay(cue.toTextOverlay(baseStyle: baseStyle, animation: animation))
        }
        return v
    }
}
