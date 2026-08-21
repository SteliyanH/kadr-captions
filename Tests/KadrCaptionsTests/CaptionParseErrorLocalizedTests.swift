import Testing
import Foundation
@testable import KadrCaptions

/// What a person sees when a subtitle file will not import.
struct CaptionParseErrorLocalizedTests {

    private static let allCases: [CaptionParseError] = [
        .unrecognizedFormat(extension: "docx"),
        .unrecognizedFormat(extension: ""),
        .malformedTimestamp(line: 42, raw: "00:00:xx,000"),
        .malformedCueIndex(line: 7, raw: "seven"),
        .missingHeader,
        .unreadableFile(URL(fileURLWithPath: "/private/var/mobile/subs/episode-2.srt")),
        .unsupportedEncoding(URL(fileURLWithPath: "/tmp/latin1.srt")),
        .malformedXML(localizedDescription: "Unexpected end of document.")
    ]

    @Test(arguments: allCases)
    func everyCaseSaysSomethingAndIsNotAnNSErrorCode(error: CaptionParseError) {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(!error.localizedDescription.contains("CaptionParseError error"))
    }

    @Test(arguments: allCases)
    func noMessageLeaksAFilesystemPath(error: CaptionParseError) {
        let text = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        #expect(!text.contains("/private/var"))
        #expect(!text.contains("/tmp/"))
    }

    @Test func aMalformedLineIsNamedBecauseThatIsWhatMakesItFixable() {
        let e = CaptionParseError.malformedTimestamp(line: 42, raw: "00:00:xx,000")
        #expect(e.errorDescription?.contains("42") == true)
        #expect(e.errorDescription?.contains("00:00:xx,000") == true)
    }

    @Test func anEmptyExtensionDoesNotProduceAStrayQuote() {
        // "“.” files aren't..." would be nonsense; the empty case reads differently.
        let text = CaptionParseError.unrecognizedFormat(extension: "").errorDescription ?? ""
        #expect(!text.contains("“.”"))
        #expect(text.contains("That file"))
    }

    @Test func theSupportedFormatsAreNamedWhenTheFormatIsWrong() {
        let s = CaptionParseError.unrecognizedFormat(extension: "docx").recoverySuggestion ?? ""
        #expect(s.contains("SRT"))
        #expect(s.contains("VTT"))
    }

    @Test func fileErrorsNameTheFileWithoutItsPath() {
        let e = CaptionParseError.unreadableFile(URL(fileURLWithPath: "/private/var/subs/episode-2.srt"))
        #expect(e.errorDescription?.contains("episode-2.srt") == true)
    }
}
