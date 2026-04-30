import Testing
import Foundation
@testable import KadrCaptions

/// Tests for v0.1 Tier 3 — `Caption.load(_:)` auto-detect dispatch.
struct CaptionLoadTests {

    @Test func dispatchesSRTByExtension() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".srt")
        try "1\n00:00:00,000 --> 00:00:02,000\nHello\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello")
    }

    @Test func dispatchesVTTByExtension() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".vtt")
        try "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nHello\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello")
    }

    @Test func dispatchIsCaseInsensitive() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".SRT")
        try "1\n00:00:00,000 --> 00:00:02,000\nUpper\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cues = try await Caption.load(tmp)
        #expect(cues.count == 1)
    }

    @Test func unrecognizedExtensionThrows() async throws {
        let url = URL(fileURLWithPath: "/tmp/captions.itt")
        await #expect(throws: CaptionParseError.self) {
            try await Caption.load(url)
        }
    }

    @Test func unrecognizedExtensionCarriesExtensionInError() async throws {
        let url = URL(fileURLWithPath: "/tmp/captions.itt")
        do {
            _ = try await Caption.load(url)
            Issue.record("expected throw")
        } catch let CaptionParseError.unrecognizedFormat(ext) {
            #expect(ext == "itt")
        } catch {
            Issue.record("expected unrecognizedFormat, got \(error)")
        }
    }

    @Test func emptyExtensionThrows() async throws {
        let url = URL(fileURLWithPath: "/tmp/captions")
        await #expect(throws: CaptionParseError.self) {
            try await Caption.load(url)
        }
    }
}
