# KadrCaptions — Design Document

## v0.1.0 design — SRT + VTT parsers and writers

The first release. Parses and authors the two most common caption file formats into kadr's `Caption` value type. iTT (.itt) is deferred to v0.2.0; styled caption mapping onto `TextOverlay` is deferred to v0.3.0+.

### Problem

kadr v0.9.2 ships the AVFoundation caption bridge (`Caption` value type, `Video.captions(_:)` modifier, engine `AVMetadataItem` writer) but stops there — by design, per the v0.9 RFC. To turn an SRT or VTT file on disk into something a kadr composition can consume, callers either parse it themselves (real-world variance: encodings, malformed timestamps, cue settings) or use this adapter.

### Scope lock

In scope:
- **SRT parser** — `Caption.load(srt: URL) async throws -> [Caption]`. UTF-8 default with Windows-1252 fallback for legacy files. CRLF / LF / mixed line endings. UTF-8 BOM tolerated. Multi-line cues. Malformed-timestamp errors.
- **VTT parser** — `Caption.load(vtt: URL) async throws -> [Caption]`. Strips cue settings (`align:`, `position:`, etc.) and inline styles (`<c.classname>...</c>`) to plain text. WebVTT header (`WEBVTT`) required.
- **Format auto-detect** — `Caption.load(_ url: URL) async throws -> [Caption]` dispatches on file extension.
- **SRT writer** — `CaptionAuthor.writeSRT(_:to:) async throws`. UTF-8, LF line endings. 1-indexed cue numbering.
- **VTT writer** — `CaptionAuthor.writeVTT(_:to:) async throws`. UTF-8, LF, `WEBVTT` header.
- **String-form parsers** — `parseSRT(_:)` / `parseVTT(_:)` taking pre-loaded `String` content. Lets callers handle non-URL sources (Bundle resource, network, etc.) without rebuilding the parser.

Out of scope (v0.2.0+ or wishlist):
- **iTT (iTunes Timed Text)** — verbose XML; larger surface; defer to v0.2.0.
- **VTT cue settings preservation** — `align:start`, `position:50%`, `line:20%`. Stripped in v0.1; revisit when the styled-caption builder lands.
- **VTT inline styles preservation** — `<c.classname>text</c>`, `<i>...</i>`. Stripped to plain text in v0.1.
- **WebVTT regions** (`REGION` blocks) — ignored.
- **WebVTT chapters / metadata cues** (NOTE blocks, `cue identifier`s) — parser tolerates but doesn't surface.
- **Styled / animated captions** — bridging onto kadr v0.8 `TextOverlay` + `textAnimation`. Defer to v0.3.0+ once real use cases exist.

### API examples

```swift
import Kadr
import KadrCaptions

// 1. Auto-detect by extension
let cues = try await Caption.load(subtitleURL)
let video = Video {
    VideoClip(url: footage)
}
.captions(cues)

// 2. Explicit format
let srt = try await Caption.load(srt: srtURL)
let vtt = try await Caption.load(vtt: vttURL)

// 3. From a string (Bundle / network)
let raw = try String(contentsOf: bundleURL)
let parsed = try CaptionParser.parseSRT(raw)

// 4. Author back to disk
try await CaptionAuthor.writeSRT(cues, to: outputSRT)
try await CaptionAuthor.writeVTT(cues, to: outputVTT)
```

### Public surface sketch

```swift
public extension Caption {
    /// Parse an SRT (SubRip) file from a URL. UTF-8 default with Windows-1252 fallback.
    static func load(srt url: URL) async throws -> [Caption]

    /// Parse a WebVTT (.vtt) file from a URL. Cue settings / inline styles are stripped
    /// to plain text in v0.1; styled-caption support arrives in v0.3.
    static func load(vtt url: URL) async throws -> [Caption]

    /// Auto-detect format by file extension and parse. Recognized: `.srt`, `.vtt`.
    /// Throws `CaptionParseError.unrecognizedFormat` for other extensions.
    static func load(_ url: URL) async throws -> [Caption]
}

public enum CaptionParser {
    /// Parse SRT content from a pre-loaded string.
    public static func parseSRT(_ content: String) throws -> [Caption]

    /// Parse WebVTT content from a pre-loaded string.
    public static func parseVTT(_ content: String) throws -> [Caption]
}

public enum CaptionAuthor {
    /// Write captions to disk as SRT. UTF-8, LF line endings, 1-indexed cue numbers.
    public static func writeSRT(_ captions: [Caption], to url: URL) async throws

    /// Write captions to disk as WebVTT. UTF-8, LF, `WEBVTT` header.
    public static func writeVTT(_ captions: [Caption], to url: URL) async throws
}

public enum CaptionParseError: Error, Equatable {
    case unrecognizedFormat(extension: String)
    case malformedTimestamp(line: Int, raw: String)
    case malformedCueIndex(line: Int, raw: String)
    case missingHeader              // WebVTT only — file didn't start with `WEBVTT`
    case unreadableFile(URL)
    case unsupportedEncoding(URL)
}
```

### Tier breakdown

Mirrors the kadr RFC-then-tiers staging.

- **Tier 0** *(this PR)* — design doc, scaffold (Package.swift, README, ROADMAP, CHANGELOG, .gitignore, LICENSE). No code.
- **Tier 1** — SRT parser + writer. ~250 LOC + tests. Ships as **v0.1.0** alongside the VTT tier? **No** — separate. Tier 1 ships first as v0.1.0-alpha or skipped: defer release until both formats land. Decision: keep them in the same release.
  - Subtier 1a — `parseSRT(_:)` string parser, UTF-8 + Windows-1252 fallback file loader, malformed-input errors.
  - Subtier 1b — `writeSRT(_:to:)` writer.
- **Tier 2** — VTT parser + writer. ~300 LOC + tests.
  - Subtier 2a — `parseVTT(_:)` string parser. Strip cue settings + inline styles.
  - Subtier 2b — `writeVTT(_:to:)` writer.
- **Tier 3** — `Caption.load(_:)` auto-detect dispatch. ~30 LOC + tests.
- **Tier 4** — Release prep + ship as **v0.1.0**. CHANGELOG, README polish, develop → main.

Each tier ships as its own PR; v0.1.0 release is held until tier 4. (Differs from kadr's "each tier as its own minor" pattern because no users are consuming intermediate adapter releases yet — first impression matters more than incremental shipping.)

### Test strategy

Pure parsing helpers carry the bulk; file I/O has a thin smoke test layer.

- **SRT parser** — well-formed single-cue, multi-line cues, multiple cues with various separators (CRLF / LF / mixed), UTF-8 BOM, malformed timestamps, malformed cue numbers, empty file, trailing whitespace.
- **VTT parser** — well-formed WEBVTT, missing header throws `.missingHeader`, cue settings stripped (`00:00:00.000 --> 00:00:01.000 align:start`), inline styles stripped (`<c.x>text</c>`, `<i>x</i>`, `<b>x</b>`, `<u>x</u>`, `<v Speaker>x</v>`), NOTE blocks ignored, REGION blocks ignored.
- **Writers** — round-trip a known `[Caption]`, parse back, assert equality. UTF-8 encoding validation. Cue numbering (SRT 1-indexed, VTT optional).
- **Encoding fallback** — synthesize a Windows-1252-encoded SRT, assert load-fallback succeeds.

Target coverage: ~30 tests across the cycle.

### Compatibility

- KadrCaptions 0.1.0 requires kadr ≥ 0.9.2 (uses `Caption`).
- Same platform floor as kadr: iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+, Swift 6.0, strict concurrency.
- No third-party dependencies. Pure Swift + Foundation.

### Open questions (track in PRs, not blocking RFC merge)

- **Whether to keep `parseSRT` / `parseVTT` synchronous and only the file loaders async.** Leaning yes — string-form parsers are pure and CPU-bound; making them `async` only buys notation cost. Decided: synchronous string-form parsers, async file loaders.
- **VTT cue identifiers.** WebVTT lets a cue have a string ID before its timestamp line. v0.1 ignores it. Revisit if the styled-caption builder needs them.
- **Numeric SRT cue index — strict or lenient?** Some real-world SRT files have non-sequential or missing indices. Lenient default: parse the timestamp line directly without requiring a numeric index. Decision: lenient.
- **Error position metadata.** Errors carry `line: Int` so callers can surface "line 42: bad timestamp." Costs minimal storage; worth it for debug ergonomics.

## v0.2.0 design — iTT (iTunes Timed Text)

Adds the third common caption format. iTT is Apple's flavor of TTML 1.0 (XML-based), used by Final Cut Pro, iTunes / Apple TV submission, and DVD-Video authoring tools. Verbose XML, but the surface that maps cleanly to v0.1's plain-text `Caption` is small.

### Problem

iTT files in the wild range from "minimal head + body cue list" (~2× the SRT size for the same content) to "full TTML with regions, styles, layout, namespaces" (~10×). The full TTML 1.0 spec is enormous; v0.2 covers what consuming apps actually receive — Final Cut export, iTunes preview, broadcast deliverables.

### Scope lock

In scope:
- **iTT parser** — `Caption.load(itt:)` async file loader + `CaptionParser.parseITT(_:)` pure string parser. Produces plain-text `Caption` values: each `<p>` element inside `<body><div>` becomes one cue. Inline `<span>` styling is flattened to plain text (same as VTT inline tags in v0.1). `<br/>` becomes `\n`. Multiple `<div>` blocks concatenate.
- **iTT writer** — `CaptionAuthor.writeITT(_:to:)` + `renderITT(_:)`. Emits a minimal valid iTT document with `xmlns="http://www.w3.org/ns/ttml"` and `xmlns:tt="http://www.w3.org/ns/ttml"`. UTF-8, LF, with the standard Apple `frameRate="30" tickRate="1000"` header.
- **Auto-detect dispatch** — extend `Caption.load(_:)` to recognize `.itt` (case-insensitive) → `load(itt:)`.
- **Time format** — `HH:MM:SS.mmm` (TTML clock-time), with `HH:MM:SS:FF` (frame-count) tolerated on read by approximating `FF / 30` since v0.2 doesn't surface frame rate in `Caption`.
- **Error path** — XML parsing failures throw `CaptionParseError.malformedTimestamp(line:raw:)` for unparseable `begin` / `end` attributes; structurally invalid XML throws a new `.malformedXML(localizedDescription:)`.

Out of scope (deferred to v0.4 styled bridge or rejected):
- **Region / style preservation** — iTT styled regions are dropped on read (mapped to plain text), same v0.3 promise as VTT. Styled output flows through the v0.3 `TextOverlay` bridge once that ships.
- **Frame-rate-aware timing** — iTT supports `tickRate` / `frameRate` / drop-frame attributes. Honored on read (approximation at the document's declared `frameRate`, or fallback 30 fps), but not surfaced on `Caption` since the type is plain time + text. Frame-accurate round-trip is a v0.4+ concern.
- **TTML namespace inheritance / nested `tt:`-prefixed attributes** — accepted but ignored. The parser reads `begin` / `end` whether or not they carry a `tt:` prefix.
- **Deeper TTML 1.0 compliance** (animations, `<set>`, multiple language tracks in one file). Out of scope; would justify its own package.

### API examples

```swift
import Kadr
import KadrCaptions

// Auto-detect
let cues = try await Caption.load(subtitleURL)  // .srt / .vtt / .itt all work

// Explicit
let cues = try await Caption.load(itt: ittURL)

// Author
try await CaptionAuthor.writeITT(cues, to: outputITT)

// String form
let raw = try String(contentsOf: bundleURL)
let parsed = try CaptionParser.parseITT(raw)
```

### Public surface sketch

```swift
public extension Caption {
    /// Parse an iTunes Timed Text (.itt) file from a URL.
    static func load(itt url: URL) async throws -> [Caption]
}

public extension CaptionParser {
    /// Parse iTT content from a pre-loaded string. Cue text is flattened to plain text;
    /// styled output flows through the v0.3 TextOverlay bridge instead.
    static func parseITT(_ content: String) throws -> [Caption]
}

public extension CaptionAuthor {
    /// Write captions to disk as iTT. UTF-8, LF, Apple-compatible header.
    static func writeITT(_ captions: [Caption], to url: URL) async throws
    /// Render iTT body for a list of captions. Pure.
    static func renderITT(_ captions: [Caption]) -> String
}

public extension CaptionParseError {
    /// XML parsing failed. The `Foundation.XMLParser` `parserError`'s description
    /// is preserved for debugging.
    case malformedXML(localizedDescription: String)
}
```

### Engine notes

- **Parser implementation.** `Foundation.XMLParser` (NSXMLParserDelegate-style) is small, fast, and dependency-free. We track a tiny state machine: in-`<body>` / in-`<div>` / in-`<p>` / collecting text. `<br/>` triggers a `"\n"` insert; closing `</p>` finalizes a cue.
- **Time-attribute parsing.** Strip `s` / `ms` suffixes (TTML allows `1.5s`, `1500ms` forms — rare in iTT but seen). Frame-count form `HH:MM:SS:FF` is parsed as `HH*3600 + MM*60 + SS + FF/30` (approximation; documented limitation).
- **Writer XML escaping.** Standard 5: `&`, `<`, `>`, `"`, `'`. iTT consumers tolerate `&apos;` / `&quot;`; we emit them.

### Tier breakdown

- **Tier 1** — `parseITT(_:)` + `Caption.load(itt:)` + `Caption.load(_:)` extension to dispatch on `.itt`. Tests for header detection, well-formed multi-cue files, malformed XML, brittle real-world FCP-export shapes, time-attribute variants. ~250 LOC + tests.
- **Tier 2** — `writeITT(_:to:)` + `renderITT(_:)`. Round-trip tests through disk. ~150 LOC + tests.
- **Tier 3** — Release prep + ship as **v0.2.0**. CHANGELOG, README polish, develop → main.

### Test strategy

- **Parser** — well-formed FCP-export shape, missing `xmlns`, `<br/>` line breaks, nested `<span>` flattening, drop-frame `HH:MM:SS:FF` timestamps approximated, `1.5s` / `1500ms` time attributes, multi-`<div>` concatenation, malformed XML throws.
- **Writer** — round-trip a known `[Caption]`; verify the produced XML re-parses to the same cues; XML escaping for special characters; UTF-8 declaration; Apple-compatible header attributes.
- **Auto-detect** — `.itt` (case-insensitive) routes to `load(itt:)`.

Target test count: ~25.

### Compatibility

- KadrCaptions 0.2.0 still requires kadr ≥ 0.9.2.
- Pure additive — every v0.1 call site compiles unchanged.

### Open questions (track in PRs, not blocking RFC merge)

- **Frame-rate handling.** v0.2 approximates frame counts at 30 fps. Real broadcast iTT files declare `frameRate="29.97"` with drop-frame; revisit if anyone hits inaccuracy.
- **Multiple `<body>` languages.** TTML allows multiple `<body>` blocks with different `xml:lang`. v0.2 reads only the first; a v0.4+ multi-language Caption surface would expose all.
- **Element name case.** TTML is XML — case-sensitive. v0.2 expects lowercase `body` / `div` / `p` / `span` / `br`. FCP and iTunes both emit lowercase; revisit if a producer ships uppercase.
