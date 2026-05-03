import Foundation
import CoreMedia
import Kadr
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        var style = StyledCaption.applyStyling(base: baseStyle, isBold: isBold, isItalic: isItalic, alignment: alignment)
        if let color, let parsed = StyledCaption.platformColor(forHex: color) {
            style.color = parsed
        }
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

    /// Parse a `#RRGGBB` or `#RRGGBBAA` hex color string into a `PlatformColor`.
    /// Returns `nil` for malformed input. Pure — exposed for tests. Added v0.5.0.
    public static func platformColor(forHex hex: String) -> PlatformColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >>  8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >>  8) & 0xFF) / 255.0
            a = Double(value & 0xFF) / 255.0
        }
        #if canImport(UIKit)
        return PlatformColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        #else
        return PlatformColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        #endif
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
