import Foundation

/// Human-readable text for every ``CaptionParseError`` case.
///
/// Without `LocalizedError` these bridge to
/// `"The operation couldn't be completed. (KadrCaptions.CaptionParseError error 3.)"`,
/// which is what a person importing a subtitle file would have been shown.
///
/// Caption files are usually not authored by the person importing them — they
/// arrive from a transcription service, a download, or a colleague. So the
/// wording assumes the reader did not write the file and cannot be expected to
/// know its internal structure: it names the line when there is one, because
/// that is the one detail that makes a malformed file fixable.
///
/// File names appear without their paths, for the same reason as elsewhere in
/// the family: a sandbox path is not something a person can act on.
extension CaptionParseError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .unrecognizedFormat(ext):
            let named = ext.isEmpty ? "That file" : "“.\(ext)” files"
            return "\(named) aren't a caption format this can read."
        case let .malformedTimestamp(line, raw):
            return "The timestamp on line \(line) couldn't be read: “\(raw)”."
        case let .malformedCueIndex(line, raw):
            return "The cue number on line \(line) couldn't be read: “\(raw)”."
        case .missingHeader:
            return "This file is missing the header its format requires."
        case let .unreadableFile(url):
            return "Couldn't open “\(url.lastPathComponent)”."
        case let .unsupportedEncoding(url):
            return "“\(url.lastPathComponent)” isn't in a text encoding this can read."
        case let .malformedXML(detail):
            return "This caption file's XML is malformed. \(detail)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unrecognizedFormat:
            return "Supported formats are SRT, VTT, iTT, ASS and SSA."
        case .malformedTimestamp, .malformedCueIndex, .missingHeader, .malformedXML:
            return "The file may be truncated, or saved in a different format from its extension."
        case .unreadableFile:
            return "The file may have moved, or may not be readable."
        case .unsupportedEncoding:
            return "Re-save it as UTF-8 and try again."
        }
    }
}
