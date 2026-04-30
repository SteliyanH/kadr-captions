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

## v0.3.0 design — Styled captions → TextOverlay bridge

The biggest leap of the cycle. v0.1 / v0.2 stripped VTT cue settings and inline styles to plain text — adequate for `AVMetadataItem` ingest, but not for visual rendering. v0.3 adds a parallel parser path that **preserves** styling, plus a bridge that maps a styled cue onto kadr v0.8's `TextOverlay` + `textAnimation`. Now consumers can render captions as styled, animated overlays baked into the video — not just as system metadata.

### Problem

A real "captions on TikTok / Reels"-style overlay can't come from `AVMetadataItem` cues: those are surfaced through the OS's caption picker, which most third-party apps don't show. Apps that want captions burned into the export need to drop styled text overlays at the cue's time range. v0.3 is that path.

### Scope lock

In scope:
- **`StyledCaption`** value type — text + timeRange + alignment + line position + bold / italic flags + speaker name. `Sendable` + `Equatable`.
- **`CaptionParser.parseStyledVTT(_:)`** — pure string parser. Same VTT shape as `parseVTT`, but cue settings (`align:`, `position:`, `line:`) and inline styles (`<i>`, `<b>`, `<u>`, `<c.classname>`, `<v Speaker>`) are **preserved** as `StyledCaption` fields rather than stripped.
- **`Caption.loadStyled(vtt:)`** — async file loader.
- **`StyledCaption.toTextOverlay(baseStyle:animation:)`** — bridge to `Kadr.TextOverlay`. Maps `alignment` → `TextStyle.Alignment`, line position → overlay `position` + `anchor`, bold flag → `TextStyle.Weight.bold`, italic flag → font selection (system italic via `.custom`), `visibilityRange` set from `timeRange`.
- **`Video.styledCaptions(_:baseStyle:animation:)`** — convenience modifier that overlays each `StyledCaption` on the composition with its own `visibilityRange`.

Out of scope (v0.3.x or later):
- **Mixed inline styling within a cue** — "`<i>partly</i> italic, `<b>partly</b>` bold" needs multiple text runs per cue. `TextOverlay` is single-style; a future version could split into multiple overlays or wait for a multi-run text type in kadr core. v0.3 collapses to "any italic in the cue → whole cue italic" (last-tag-wins behavior is rare in the wild).
- **Styled iTT bridge** — iTT styling is much bigger (CSS-style `tts:color`, `tts:fontSize`, regions). Defer to v0.3.x or v0.4+ on demand. v0.3 ships VTT-only on the styled path.
- **`<u>` underline** — `Kadr.TextStyle` has no underline field today. Surfaced on `StyledCaption.isUnderlined` for forward compat but doesn't affect the overlay output until kadr core grows it.
- **`<c.classname>`-driven styling** — v0.3 records the classnames on `StyledCaption.classes: [String]` but doesn't apply them. Real WebVTT styling needs a `STYLE` block parser to map classnames to colors / fonts; defer to v0.3.x.
- **Per-character animation** (typewriter / kinetic captions) — would require kadr v0.8's `textAnimation` to support "reveal by character." The bridge passes through whatever `animation` argument the caller hands in; per-character text isn't a v0.3 concern.

### API examples

```swift
import Kadr
import KadrCaptions

// 1. Parse + bridge in one go
let cues = try await Caption.loadStyled(vtt: vttURL)
let video = Video {
    VideoClip(url: footage)
}
.styledCaptions(cues)

// 2. Customize the base style (font / color) — the parser's bold/italic flags
// override the base style's weight when set.
var titleStyle = TextStyle.default
titleStyle.fontSize = 56
titleStyle.color = .white
let video2 = Video {
    VideoClip(url: footage)
}
.styledCaptions(cues, baseStyle: titleStyle)

// 3. Add a fade-in animation to every styled caption
let video3 = Video {
    VideoClip(url: footage)
}
.styledCaptions(cues, animation: .fadeIn(duration: 0.3))

// 4. Hand-built styled caption (no file)
let cue = StyledCaption(
    text: "MY MOVIE",
    timeRange: CMTimeRange(start: .zero, duration: cmt(2)),
    alignment: .center,
    line: .top,
    position: 0.5,
    isBold: true,
    isItalic: false,
    speaker: nil,
    classes: []
)
let overlay = cue.toTextOverlay()
```

### Public surface sketch

```swift
public struct StyledCaption: Sendable, Equatable {
    public let text: String
    public let timeRange: CMTimeRange
    /// Horizontal alignment of the cue text within its layout box. Maps to
    /// `Kadr.TextStyle.Alignment`.
    public let alignment: StyledCaptionAlignment
    /// Vertical placement on the render canvas. WebVTT's `line:` setting.
    public let line: StyledCaptionLine
    /// Horizontal position in `0...1`. WebVTT's `position:` setting; default `0.5`
    /// (centered).
    public let position: Double
    public let isBold: Bool
    public let isItalic: Bool
    /// `<u>` underline. Recorded for forward compatibility; not yet rendered (kadr
    /// `TextStyle` doesn't expose underline as of kadr 0.9).
    public let isUnderlined: Bool
    /// `<v Speaker>` tag's payload, if present. Useful for callers wanting to
    /// prepend the speaker's name in their own overlay layout.
    public let speaker: String?
    /// Classnames from `<c.foo.bar>...</c>` tags. Recorded for forward compat with
    /// the v0.3.x `<STYLE>`-block parser.
    public let classes: [String]
}

public enum StyledCaptionAlignment: Sendable, Equatable {
    case start    // == .leading in TextStyle
    case center
    case end      // == .trailing in TextStyle
}

public enum StyledCaptionLine: Sendable, Equatable {
    /// Default WebVTT placement — bottom of the render canvas.
    case auto
    case top
    case bottom
    /// Explicit vertical position in `0...100` (percent of canvas height from top).
    case percent(Double)
}

public extension CaptionParser {
    static func parseStyledVTT(_ content: String) throws -> [StyledCaption]
}

public extension Caption {
    static func loadStyled(vtt url: URL) async throws -> [StyledCaption]
}

public extension StyledCaption {
    /// Build a `TextOverlay` rendering this caption. `baseStyle`'s font / color /
    /// weight apply unless overridden by the cue's own bold / italic flags.
    /// `visibilityRange` is set from `timeRange`. If `animation` is non-nil it's
    /// attached unchanged.
    func toTextOverlay(
        baseStyle: TextStyle = .default,
        animation: (any TextAnimation)? = nil
    ) -> TextOverlay
}

public extension Video {
    /// Overlay every styled caption onto the composition. Each becomes a
    /// `TextOverlay` with its own `visibilityRange` and the supplied base style /
    /// animation.
    func styledCaptions(
        _ captions: [StyledCaption],
        baseStyle: TextStyle = .default,
        animation: (any TextAnimation)? = nil
    ) -> Video
}
```

### Engine notes

- **Reuse VTT block / cue scanning.** `parseStyledVTT` shares the WEBVTT-header / NOTE / REGION / STYLE / cue-identifier skipping with `parseVTT`. The difference is in handling the timestamp line's trailing settings and the cue-text's inline tags.
- **Cue setting parsing.** Tokenize the trailing portion of the timestamp line by whitespace, then split each token on the first `:`. Recognize `align`, `line`, `position`. Unrecognized settings are ignored.
- **Inline tag handling.** Scan the cue text for `<...>` tags. For each tag:
  - `<i>` / `</i>`, `<b>` / `</b>`, `<u>` / `</u>` → toggle the respective flag on the cue (`isItalic` / `isBold` / `isUnderlined`).
  - `<c.foo.bar>` → record `["foo", "bar"]` in `classes` (additive across tags).
  - `<v Speaker>...</v>` → record `Speaker` as `speaker`.
  - `<00:00:01.500>` → ignored (timed-text marker, no plain-text equivalent).
  - All tags are stripped from the resulting `text` field; the styling is recorded as flags / classes / speaker.
- **Bridge math.** `StyledCaptionLine.auto` / `.bottom` → overlay `position = .normalized(x: position, y: 0.92)`, `anchor = .bottom`. `.top` → `y: 0.08`, `anchor = .top`. `.percent(p)` → `y: p / 100.0`, anchor follows whichever side it's nearer to (top half → `.top`, bottom half → `.bottom`).
- **Italic via custom font.** kadr `TextStyle` has no italic flag. The bridge synthesizes italic by passing a system italic font name (`"Helvetica-Oblique"` / `"-apple-system,italic"` not portable; we use `"Helvetica-Oblique"` which is available on every Apple platform). Documented limitation; revisit when kadr `TextStyle` grows an italic field.

### Tier breakdown

- **Tier 1** — `StyledCaption` value type + `parseStyledVTT` + `Caption.loadStyled(vtt:)`. ~300 LOC + tests.
- **Tier 2** — `StyledCaption.toTextOverlay(baseStyle:animation:)` + `Video.styledCaptions(_:baseStyle:animation:)`. ~120 LOC + tests.
- **Tier 3** — Release prep + ship as **v0.3.0**.

### Test strategy

- **Parser** — well-formed cue with `align:start position:25%` settings → `StyledCaption.alignment == .start`, `position == 0.25`. Inline tag flag toggling: `<i>...</i>`, `<b>...</b>`, `<u>...</u>`, nested combinations. `<v Speaker>` extraction. `<c.foo.bar>` classnames. Multi-cue documents with mixed styling. Round-trip through `parseStyledVTT` + `parseVTT` plain text agreement (the styled parser's stripped text == plain parser's text).
- **Bridge** — alignment mapping (`.start` → `TextStyle.Alignment.leading`), line mapping (`.top` / `.bottom` / `.percent(50)`), bold flag → `TextStyle.Weight.bold`, italic flag → italic font name, `visibilityRange` matches `timeRange`, animation passed through.
- **`Video.styledCaptions`** — adds N overlays for N captions; each overlay's `layerID` is unique (auto-generated from the caption index); base style applied unless the cue overrides.

Target test count: ~40 new tests across the cycle. Suite floor: 98 → ~138.

### Compatibility

- KadrCaptions 0.3.0 still requires kadr ≥ 0.9.2 (uses `TextOverlay`, `TextStyle`, `TextAnimation`).
- Pure additive — every v0.2 call site compiles unchanged.

### Open questions (track in PRs, not blocking RFC merge)

- **Per-cue line-height / leading.** kadr `TextStyle` doesn't expose it. v0.3 doesn't surface it either; revisit.
- **Right-to-left / vertical text.** WebVTT supports `vertical:rl` / `vertical:lr`. v0.3 ignores. Revisit if anyone hits a real RTL caption file.
- **Multi-language `<lang>` tags.** Surfaced as `classes` with the language tag prefixed (`["lang:fr"]`)? Or a separate field? Defer until demand.
- **`<STYLE>` block parsing.** Needed for `<c.classname>`-driven styling to actually apply. v0.3 records classnames; v0.3.x parser maps them to fonts / colors. Tracked separately.

## v0.4.0 design — ASS / SSA

The fourth and final caption format. Advanced SubStation Alpha (.ass) and its predecessor SubStation Alpha (.ssa) are heavily used in anime / fansub / streaming pipelines. They share a common structure (INI-style sections + CSV-like event lines) but differ in style-block schemas. v0.4 ships plain-text parsing + authoring; styled-text override codes (`{\b1}`, `{\i1}`, `{\c&HFFFFFF&}`) are stripped, mirroring v0.1's VTT inline-tag policy.

### Problem

ASS / SSA dominate fansub and anime release pipelines, and increasingly show up in streaming-platform deliverables (Crunchyroll, HIDIVE, Netflix anime). Apps that ingest community subtitles need this format. Surface for plain-text reading is small (~250 LOC); authoring is similar (~150 LOC). Together they finish the "common subtitle format" matrix.

### Scope lock

In scope:
- **`Caption.load(ass:)`** + **`CaptionParser.parseASS(_:)`** — plain-text ASS parser. Reads the `[Events]` section's `Format:` line to discover column order, then emits one `Caption` per `Dialogue:` line. `\N` and `\n` (literal backslash-n) become `\n` line breaks. Style override blocks like `{\b1}bold{\b0}` and `{\c&HFFFFFF&}color` are stripped.
- **`Caption.load(ssa:)`** + **`CaptionParser.parseSSA(_:)`** — SSA parser. Same logic as ASS — the differences are in the style block (which we don't surface) and the timestamp-precision claim (both use centiseconds in practice). Implementation reuses the ASS path; the public split is for clarity at the call site.
- **`CaptionAuthor.writeASS(_:to:)`** + **`renderASS(_:)`** — minimal valid ASS document with default style.
- **`CaptionAuthor.writeSSA(_:to:)`** + **`renderSSA(_:)`** — minimal valid SSA document.
- **Auto-detect dispatch** — `Caption.load(_:)` extended to recognize `.ass` and `.ssa` (case-insensitive).
- **Time helpers** — `parseASSTimestamp(_:)`, `formatASSTimestamp(_:)` for `H:MM:SS.cc` (centisecond precision).

Out of scope (v0.4.x or rejected):
- **Style override preservation** — `{\b1}`, `{\i1}`, `{\fn...}`, `{\c...}`, etc. preserved as styling. v0.4 strips; styled output flows through v0.3's `TextOverlay` bridge if anyone wants it (would justify a `parseStyledASS` parallel to `parseStyledVTT`). Defer.
- **Karaoke timing tags** — `{\k50}`, `{\K50}`, `{\kf50}`, `{\ko50}` (per-syllable timing). Stripped to plain text in v0.4.
- **`[V4+ Styles]` / `[V4 Styles]` block parsing** — style definitions ignored; the `Style` reference on each `Dialogue:` line isn't surfaced. Bridges to per-cue styling would land alongside the styled-ASS parser.
- **Drawing commands** — `{\p1}...{\p0}` (vector graphics). Stripped.
- **`Comment:` events** — treated as non-rendered (skipped on read; not emitted on write).
- **Per-cue Layer / MarginL / MarginR / MarginV / Effect** — fields read off the format line are recognized but their values aren't surfaced on `Caption`. Recorded as forward-compat scaffolding only if styled bridge ships later.

### API examples

```swift
import Kadr
import KadrCaptions

// Auto-detect
let cues = try await Caption.load(subtitleURL)  // .srt / .vtt / .itt / .ass / .ssa

// Explicit
let cues = try await Caption.load(ass: assURL)

// Author
try await CaptionAuthor.writeASS(cues, to: outputASS)
```

### Public surface sketch

```swift
public extension Caption {
    static func load(ass url: URL) async throws -> [Caption]
    static func load(ssa url: URL) async throws -> [Caption]
}

public extension CaptionParser {
    static func parseASS(_ content: String) throws -> [Caption]
    static func parseSSA(_ content: String) throws -> [Caption]
    static func parseASSTimestamp(_ raw: String) -> CMTime?
    static func stripASSOverrides(_ text: String) -> String
}

public extension CaptionAuthor {
    static func writeASS(_ captions: [Caption], to url: URL) async throws
    static func writeSSA(_ captions: [Caption], to url: URL) async throws
    static func renderASS(_ captions: [Caption]) -> String
    static func renderSSA(_ captions: [Caption]) -> String
    static func formatASSTimestamp(_ time: CMTime) -> String
}
```

No new error cases; existing `CaptionParseError.malformedTimestamp(line:raw:)` covers bad time fields, `unrecognizedFormat` covers unknown extensions.

### Engine notes

- **Section detection.** Walk lines; a `[Header]` line opens a section. Within `[Events]`, the first `Format:` line declares the field order — typically `Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`. We need only the indices for `Start`, `End`, and `Text`; everything else is consumed and discarded.
- **CSV row split.** `Dialogue:` lines split on `,` *with a hard limit of N-1 commas*, where N is the field count. The trailing `Text` field can contain commas and must not be split. Standard ASS parsers do this; we replicate the rule.
- **Override block scanner.** `{...}` runs anywhere in `Text` are stripped. `\N` / `\n` (literal) → `\n`. `\h` (non-breaking space) → space. Drawing-mode segments (`{\p1}...{\p0}`) emit nothing for the geometry data between them.
- **Timestamp parsing.** ASS time is `H:MM:SS.cc` (`H` not zero-padded; centiseconds, not milliseconds). Convert to `CMTime` at timescale 1000 (`cs * 10` for the millisecond digits).
- **Writer.** Emit a minimal `[Script Info]` (title + `ScriptType: v4.00+` for ASS, `v4.00` for SSA), an empty `[V4+ Styles]` / `[V4 Styles]` with a Default style row, and an `[Events]` block with our standard 10-field format. Dialogue text is escaped: `,` → `\,`, `\n` → `\N`, `\` → `\\`, `{` → `\{`, `}` → `\}`.

### Tier breakdown

- **Tier 1** — `parseASS` + `parseSSA` + `Caption.load(ass:)` + `Caption.load(ssa:)` + auto-detect. ~300 LOC + tests.
- **Tier 2** — `writeASS` + `writeSSA` + render helpers. ~200 LOC + tests.
- **Tier 3** — Release prep + ship as **v0.4.0**.

### Test strategy

- **Parser** — minimal valid ASS / SSA, multi-line via `\N` and `\n`, override codes stripped, CSV row split with comma in text, comments skipped, malformed timestamps throw, missing `[Events]` section yields empty array.
- **Time** — round-trip H:MM:SS.cc, centisecond precision, padded values.
- **Writer** — round-trip a `[Caption]` through render → parse, escape characters, comma-in-text handling.
- **Auto-detect** — `.ass` / `.ssa` (case-insensitive) routes correctly.

Target: ~30 new tests across the cycle. Suite: 155 → ~185.

### Compatibility

- Still requires kadr ≥ 0.9.2.
- Pure additive — every v0.3 call site compiles unchanged.

### Open questions (track in PRs, not blocking RFC merge)

- **`Comment:` round-trip.** Skipped on read. Should the writer emit any of the original metadata? v0.4 says no — round-tripping a parsed cue produces only the dialogue. Revisit if anyone needs to preserve provenance.
- **Frame-rate-aware timing.** SSA / ASS files don't carry a frame rate (broadcast-style timecodes don't apply); centisecond precision is enough. No drop-frame concerns.
- **Multi-language scripts.** SSA / ASS support multiple `Style` definitions but only one events block; multi-language subtitle files are typically distributed as separate files per language. v0.4 doesn't surface style metadata.
- **Karaoke timing.** Stripped in v0.4. A future styled-ASS surface could expose per-syllable timing as something kadr-ui could render — but that's a major scope expansion. Defer indefinitely.
