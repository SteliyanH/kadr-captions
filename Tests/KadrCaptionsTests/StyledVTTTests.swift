import Testing
import CoreMedia
import Foundation
@testable import KadrCaptions

/// Tests for v0.3 Tier 1 — StyledCaption value type, parseStyledVTT, helper functions.
struct StyledVTTTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    // MARK: - parseStyledVTTTimestampLine

    @Test func parsesTimestampLineWithoutSettings() {
        let result = CaptionParser.parseStyledVTTTimestampLine("00:00:00.000 --> 00:00:02.500")
        #expect(result != nil)
        #expect(result!.1 == "")
    }

    @Test func parsesTimestampLineWithSettings() {
        let result = CaptionParser.parseStyledVTTTimestampLine(
            "00:00:00.000 --> 00:00:02.500 align:start position:25%"
        )
        #expect(result != nil)
        #expect(result!.1 == "align:start position:25%")
    }

    // MARK: - parseVTTCueSettings

    @Test func parsesAlignSetting() {
        #expect(CaptionParser.parseVTTCueSettings("align:start").alignment == .start)
        #expect(CaptionParser.parseVTTCueSettings("align:center").alignment == .center)
        #expect(CaptionParser.parseVTTCueSettings("align:end").alignment == .end)
    }

    @Test func parsesAlignLegacyValues() {
        #expect(CaptionParser.parseVTTCueSettings("align:left").alignment == .start)
        #expect(CaptionParser.parseVTTCueSettings("align:right").alignment == .end)
        #expect(CaptionParser.parseVTTCueSettings("align:middle").alignment == .center)
    }

    @Test func parsesPositionPercent() {
        let s = CaptionParser.parseVTTCueSettings("position:25%")
        #expect(abs(s.position - 0.25) < 0.0001)
    }

    @Test func parsesLineSettings() {
        #expect(CaptionParser.parseVTTCueSettings("line:auto").line == .auto)
        #expect(CaptionParser.parseVTTCueSettings("line:0%").line == .top)
        #expect(CaptionParser.parseVTTCueSettings("line:100%").line == .bottom)
        if case .percent(let v) = CaptionParser.parseVTTCueSettings("line:50%").line {
            #expect(abs(v - 50) < 0.001)
        } else {
            Issue.record("expected .percent")
        }
    }

    @Test func parsesMultipleSettings() {
        let s = CaptionParser.parseVTTCueSettings("align:start position:25% line:0%")
        #expect(s.alignment == .start)
        #expect(abs(s.position - 0.25) < 0.0001)
        #expect(s.line == .top)
    }

    @Test func ignoresUnrecognizedSettings() {
        let s = CaptionParser.parseVTTCueSettings("region:r1 align:end vertical:rl")
        #expect(s.alignment == .end)
    }

    @Test func defaultsForEmptyInput() {
        let s = CaptionParser.parseVTTCueSettings("")
        #expect(s.alignment == .center)
        #expect(s.line == .auto)
        #expect(s.position == 0.5)
    }

    // MARK: - extractStyledRuns

    @Test func plainTextHasNoFlags() {
        let r = CaptionParser.extractStyledRuns("plain text")
        #expect(r.text == "plain text")
        #expect(!r.isBold)
        #expect(!r.isItalic)
        #expect(!r.isUnderlined)
        #expect(r.speaker == nil)
        #expect(r.classes.isEmpty)
    }

    @Test func extractsItalicFlag() {
        let r = CaptionParser.extractStyledRuns("<i>Hello</i> world")
        #expect(r.text == "Hello world")
        #expect(r.isItalic)
        #expect(!r.isBold)
    }

    @Test func extractsBoldFlag() {
        let r = CaptionParser.extractStyledRuns("<b>Hello</b>")
        #expect(r.text == "Hello")
        #expect(r.isBold)
    }

    @Test func extractsUnderlineFlag() {
        let r = CaptionParser.extractStyledRuns("<u>Hello</u>")
        #expect(r.isUnderlined)
    }

    @Test func extractsSpeakerName() {
        let r = CaptionParser.extractStyledRuns("<v Speaker>Hello</v>")
        #expect(r.text == "Hello")
        #expect(r.speaker == "Speaker")
    }

    @Test func extractsMultiWordSpeaker() {
        let r = CaptionParser.extractStyledRuns("<v Jane Doe>Hi</v>")
        #expect(r.speaker == "Jane Doe")
    }

    @Test func extractsClassNames() {
        let r = CaptionParser.extractStyledRuns("<c.bold.red>Hello</c>")
        #expect(r.text == "Hello")
        #expect(r.classes == ["bold", "red"])
    }

    @Test func skipsTimedTextMarkers() {
        let r = CaptionParser.extractStyledRuns("First <00:00:01.500>Second")
        #expect(r.text == "First Second")
    }

    @Test func handlesNestedTags() {
        let r = CaptionParser.extractStyledRuns("<i>italic <b>and bold</b></i>")
        #expect(r.text == "italic and bold")
        #expect(r.isItalic)
        #expect(r.isBold)
    }

    // MARK: - parseStyledVTT — happy paths

    @Test func parsesSingleCueWithDefaults() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        Hello world
        """
        let cues = try! CaptionParser.parseStyledVTT(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello world")
        #expect(cues[0].alignment == .center)
        #expect(cues[0].line == .auto)
        #expect(cues[0].position == 0.5)
        #expect(!cues[0].isBold)
        #expect(!cues[0].isItalic)
    }

    @Test func parsesCueWithAlignmentAndPosition() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500 align:start position:25%
        Hello
        """
        let cues = try! CaptionParser.parseStyledVTT(vtt)
        #expect(cues[0].alignment == .start)
        #expect(abs(cues[0].position - 0.25) < 0.0001)
    }

    @Test func parsesCueWithInlineStyle() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        <i>Italic</i> and <b>bold</b>
        """
        let cues = try! CaptionParser.parseStyledVTT(vtt)
        #expect(cues[0].text == "Italic and bold")
        #expect(cues[0].isItalic)
        #expect(cues[0].isBold)
    }

    @Test func parsesCueWithSpeakerAndClasses() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        <v Jane><c.title.red>Welcome</c></v>
        """
        let cues = try! CaptionParser.parseStyledVTT(vtt)
        #expect(cues[0].text == "Welcome")
        #expect(cues[0].speaker == "Jane")
        #expect(cues[0].classes == ["title", "red"])
    }

    @Test func parsesMultipleCuesWithMixedStyling() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000 align:start
        <i>First</i>

        00:00:02.000 --> 00:00:04.000 align:end position:75%
        <b>Second</b>
        """
        let cues = try! CaptionParser.parseStyledVTT(vtt)
        #expect(cues.count == 2)
        #expect(cues[0].alignment == .start)
        #expect(cues[0].isItalic)
        #expect(cues[1].alignment == .end)
        #expect(abs(cues[1].position - 0.75) < 0.0001)
        #expect(cues[1].isBold)
    }

    @Test func plainTextAgreesWithParseVTT() {
        // Critical contract: the plain-text part of every styled cue equals the
        // text parseVTT would produce for the same input.
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        <i>Hello</i> <b>world</b>
        Line two with <c.x>class</c>
        """
        let plain = try! CaptionParser.parseVTT(vtt)
        let styled = try! CaptionParser.parseStyledVTT(vtt)
        #expect(plain.count == styled.count)
        for (p, s) in zip(plain, styled) {
            #expect(p.text == s.text)
        }
    }

    @Test func multiLineCueAccumulatesStyling() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        <i>First</i> line
        <b>Second</b> line
        """
        let cues = try! CaptionParser.parseStyledVTT(vtt)
        #expect(cues[0].text == "First line\nSecond line")
        #expect(cues[0].isItalic)
        #expect(cues[0].isBold)
    }

    // MARK: - parseStyledVTT — error paths

    @Test func throwsOnMissingHeader() {
        let body = "00:00:00.000 --> 00:00:01.000\nText\n"
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseStyledVTT(body)
        }
    }

    @Test func throwsOnMalformedTimestamp() {
        let vtt = "WEBVTT\n\nnot a timestamp\nText\n"
        #expect(throws: CaptionParseError.self) {
            try CaptionParser.parseStyledVTT(vtt)
        }
    }

    // MARK: - File loader

    @Test func loadStyledReadsVTT() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".vtt")
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000 align:end
        <i>Hello</i>
        """
        try vtt.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.loadStyled(vtt: tmp)
        #expect(cues.count == 1)
        #expect(cues[0].alignment == .end)
        #expect(cues[0].isItalic)
        #expect(cues[0].text == "Hello")
    }

    // MARK: - StyledCaption value type

    @Test func styledCaptionIsEquatable() {
        let a = StyledCaption(
            text: "Hi",
            timeRange: CMTimeRange(start: .zero, duration: cmt(1))
        )
        let b = StyledCaption(
            text: "Hi",
            timeRange: CMTimeRange(start: .zero, duration: cmt(1))
        )
        let c = StyledCaption(
            text: "Hi",
            timeRange: CMTimeRange(start: .zero, duration: cmt(1)),
            isBold: true
        )
        #expect(a == b)
        #expect(a != c)
    }

    @Test func styledCaptionDefaultsAreReasonable() {
        let c = StyledCaption(
            text: "X",
            timeRange: CMTimeRange(start: .zero, duration: cmt(1))
        )
        #expect(c.alignment == .center)
        #expect(c.line == .auto)
        #expect(c.position == 0.5)
        #expect(!c.isBold)
        #expect(!c.isItalic)
        #expect(!c.isUnderlined)
        #expect(c.speaker == nil)
        #expect(c.classes.isEmpty)
    }
}
