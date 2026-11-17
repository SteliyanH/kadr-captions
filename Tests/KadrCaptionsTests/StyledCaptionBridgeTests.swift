import Testing
import CoreMedia
import Foundation
import Kadr
@testable import KadrCaptions

/// Tests for v0.3 Tier 2 — StyledCaption.toTextOverlay bridge + Video.styledCaptions.
struct StyledCaptionBridgeTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    private func cue(
        text: String = "X",
        duration: Double = 1.0,
        alignment: StyledCaptionAlignment = .center,
        line: StyledCaptionLine = .auto,
        position: Double = 0.5,
        isBold: Bool = false,
        isItalic: Bool = false
    ) -> StyledCaption {
        StyledCaption(
            text: text,
            timeRange: CMTimeRange(start: .zero, duration: cmt(duration)),
            alignment: alignment,
            line: line,
            position: position,
            isBold: isBold,
            isItalic: isItalic
        )
    }

    // MARK: - mapAlignment

    @Test func alignmentMapsToTextStyleAlignment() {
        #expect(StyledCaption.mapAlignment(.start) == .leading)
        #expect(StyledCaption.mapAlignment(.center) == .center)
        #expect(StyledCaption.mapAlignment(.end) == .trailing)
    }

    // MARK: - applyStyling

    @Test func applyStylingHonorsBoldFlag() {
        let s = StyledCaption.applyStyling(base: .default, isBold: true, isItalic: false, alignment: .center)
        #expect(s.weight == .bold)
    }

    @Test func applyStylingPreservesNonBoldWeight() {
        var base = TextStyle.default
        base.weight = .medium
        let s = StyledCaption.applyStyling(base: base, isBold: false, isItalic: false, alignment: .center)
        #expect(s.weight == .medium)
    }

    @Test func applyStylingHonorsItalicFlag() {
        let s = StyledCaption.applyStyling(base: .default, isBold: false, isItalic: true, alignment: .center)
        #expect(s.fontName == "Helvetica-Oblique")
    }

    @Test func applyStylingPreservesFontWhenNotItalic() {
        var base = TextStyle.default
        base.fontName = "Avenir"
        let s = StyledCaption.applyStyling(base: base, isBold: false, isItalic: false, alignment: .center)
        #expect(s.fontName == "Avenir")
    }

    @Test func applyStylingOverridesAlignment() {
        var base = TextStyle.default
        base.alignment = .leading
        let s = StyledCaption.applyStyling(base: base, isBold: false, isItalic: false, alignment: .end)
        #expect(s.alignment == .trailing)
    }

    // MARK: - overlayPosition

    @Test func bottomLineMapsToY92() {
        if case .normalized(_, let y) = StyledCaption.overlayPosition(line: .auto, position: 0.5) {
            #expect(abs(y - 0.92) < 0.0001)
        } else {
            Issue.record("expected .normalized")
        }
        if case .normalized(_, let y) = StyledCaption.overlayPosition(line: .bottom, position: 0.5) {
            #expect(abs(y - 0.92) < 0.0001)
        } else {
            Issue.record("expected .normalized")
        }
    }

    @Test func topLineMapsToY08() {
        if case .normalized(_, let y) = StyledCaption.overlayPosition(line: .top, position: 0.5) {
            #expect(abs(y - 0.08) < 0.0001)
        } else {
            Issue.record("expected .normalized")
        }
    }

    @Test func percentLineMapsLinearly() {
        if case .normalized(_, let y) = StyledCaption.overlayPosition(line: .percent(25), position: 0.5) {
            #expect(abs(y - 0.25) < 0.0001)
        } else {
            Issue.record("expected .normalized")
        }
    }

    @Test func positionMapsToX() {
        if case .normalized(let x, _) = StyledCaption.overlayPosition(line: .auto, position: 0.25) {
            #expect(abs(x - 0.25) < 0.0001)
        } else {
            Issue.record("expected .normalized")
        }
    }

    // MARK: - overlayAnchor

    @Test func bottomLineAnchorByAlignment() {
        #expect(StyledCaption.overlayAnchor(line: .bottom, alignment: .start) == .bottomLeft)
        #expect(StyledCaption.overlayAnchor(line: .bottom, alignment: .center) == .bottom)
        #expect(StyledCaption.overlayAnchor(line: .bottom, alignment: .end) == .bottomRight)
    }

    @Test func topLineAnchorByAlignment() {
        #expect(StyledCaption.overlayAnchor(line: .top, alignment: .start) == .topLeft)
        #expect(StyledCaption.overlayAnchor(line: .top, alignment: .center) == .top)
        #expect(StyledCaption.overlayAnchor(line: .top, alignment: .end) == .topRight)
    }

    @Test func autoLineAnchorIsBottom() {
        #expect(StyledCaption.overlayAnchor(line: .auto, alignment: .center) == .bottom)
    }

    @Test func percentLineAnchorBranchesAtMidline() {
        #expect(StyledCaption.overlayAnchor(line: .percent(25), alignment: .center) == .top)
        #expect(StyledCaption.overlayAnchor(line: .percent(75), alignment: .center) == .bottom)
        #expect(StyledCaption.overlayAnchor(line: .percent(50), alignment: .center) == .bottom)
    }

    // MARK: - toTextOverlay

    @Test func toTextOverlayAttachesText() {
        let overlay = cue(text: "Hello").toTextOverlay()
        #expect(overlay.text == "Hello")
    }

    @Test func toTextOverlaySetsVisibilityRangeFromTimeRange() {
        let c = StyledCaption(
            text: "X",
            timeRange: CMTimeRange(start: cmt(2.0), duration: cmt(3.0))
        )
        let overlay = c.toTextOverlay()
        #expect(overlay.visibilityRange != nil)
        if let range = overlay.visibilityRange {
            #expect(abs(CMTimeGetSeconds(range.start) - 2.0) < 0.001)
            #expect(abs(CMTimeGetSeconds(range.duration) - 3.0) < 0.001)
        }
    }

    @Test func toTextOverlayHonorsAlignment() {
        let overlay = cue(alignment: .start).toTextOverlay()
        #expect(overlay.style.alignment == .leading)
    }

    @Test func toTextOverlayHonorsBoldFlag() {
        let overlay = cue(isBold: true).toTextOverlay()
        #expect(overlay.style.weight == .bold)
    }

    @Test func toTextOverlayHonorsItalicFlag() {
        let overlay = cue(isItalic: true).toTextOverlay()
        #expect(overlay.style.fontName == "Helvetica-Oblique")
    }

    @Test func toTextOverlayPassesAnimationThrough() {
        let anim: any TextAnimation = .fadeIn(duration: 0.5)
        let overlay = cue().toTextOverlay(animation: anim)
        #expect(overlay.textAnimation != nil)
    }

    @Test func toTextOverlayDefaultAnimationIsNil() {
        let overlay = cue().toTextOverlay()
        #expect(overlay.textAnimation == nil)
    }

    @Test func toTextOverlayUsesProvidedBaseStyle() {
        var base = TextStyle.default
        base.fontSize = 64
        let overlay = cue().toTextOverlay(baseStyle: base)
        #expect(overlay.style.fontSize == 64)
    }

    // MARK: - Video.styledCaptions

    @Test func styledCaptionsAddsOneOverlayPerCue() {
        let cues = [
            cue(text: "A", duration: 1),
            cue(text: "B", duration: 1),
            cue(text: "C", duration: 1),
        ]
        let video = Video {
            ImageClip(PlatformImage(), duration: 5.0)
        }
        .styledCaptions(cues)
        #expect(video.overlays.count == 3)
    }

    @Test func styledCaptionsPreservesExistingOverlays() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 5.0)
        }
        .overlay(TextOverlay("title"))
        .styledCaptions([cue(text: "X")])
        #expect(video.overlays.count == 2)
    }

    @Test func multipleStyledCaptionsCallsAccumulate() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 5.0)
        }
        .styledCaptions([cue(text: "A")])
        .styledCaptions([cue(text: "B"), cue(text: "C")])
        #expect(video.overlays.count == 3)
    }

    @Test func styledCaptionsAppliesBaseStyle() {
        var base = TextStyle.default
        base.fontSize = 48
        let video = Video {
            ImageClip(PlatformImage(), duration: 5.0)
        }
        .styledCaptions([cue(text: "X")], baseStyle: base)
        guard let overlay = video.overlays.first as? TextOverlay else {
            Issue.record("expected TextOverlay")
            return
        }
        #expect(overlay.style.fontSize == 48)
    }

    @Test func styledCaptionsAttachesAnimationToEveryCue() {
        let cues = [cue(text: "A"), cue(text: "B")]
        let video = Video {
            ImageClip(PlatformImage(), duration: 5.0)
        }
        .styledCaptions(cues, animation: .fadeIn(duration: 0.5))
        let textOverlays = video.overlays.compactMap { $0 as? TextOverlay }
        #expect(textOverlays.count == 2)
        #expect(textOverlays.allSatisfy { $0.textAnimation != nil })
    }

    // MARK: - Where the burned-in text lands

    /// The box kadr (1.2 and later) draws an un-sized caption in: its text's own
    /// size, placed by the caption's position and anchor. Before kadr 1.2 that box
    /// was the whole canvas, so a bottom caption's box ran from above the top of the
    /// frame down to 92%, and its text was drawn near the top.
    private func exportFrame(_ overlay: TextOverlay, in canvas: CGSize) -> CGRect {
        let natural = overlay.naturalSize(in: canvas)
        return Kadr.Layout.resolveFrame(
            position: overlay.position,
            size: overlay.size ?? .pixels(width: Double(natural.width), height: Double(natural.height)),
            anchor: overlay.anchor,
            in: canvas
        )
    }

    @Test func bottomCaptionSitsAtTheBottom() {
        let canvas = CGSize(width: 1080, height: 1920)
        let overlay = cue(text: "Bottom line").toTextOverlay(baseStyle: TextStyle(fontSize: 48))
        #expect(overlay.size == nil, "captions rely on kadr's text-sized box")
        let frame = exportFrame(overlay, in: canvas)
        #expect(abs(frame.maxY - canvas.height * 0.92) < 1, "text bottom at the 92% line")
        #expect(frame.minY > canvas.height * 0.8, "text in the lower part of the frame, top at \(frame.minY)")
        #expect(abs(frame.midX - canvas.width / 2) < 1)
    }

    @Test func topCaptionSitsAtTheTop() {
        let canvas = CGSize(width: 1920, height: 1080)
        let overlay = cue(text: "Top line", line: .top).toTextOverlay(baseStyle: TextStyle(fontSize: 48))
        let frame = exportFrame(overlay, in: canvas)
        #expect(abs(frame.minY - canvas.height * 0.08) < 1, "text top at the 8% line")
        #expect(frame.maxY < canvas.height * 0.25)
    }

    @Test func longCaptionWrapsInsideTheFrame() {
        let canvas = CGSize(width: 1080, height: 1920)
        let text = String(repeating: "a long caption line ", count: 8)
        let frame = exportFrame(cue(text: text).toTextOverlay(baseStyle: TextStyle(fontSize: 48)), in: canvas)
        #expect(frame.width <= canvas.width)
        #expect(frame.minX >= 0 && frame.maxX <= canvas.width)
        #expect(frame.minY > 0, "every line on screen")
    }
}
