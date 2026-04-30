# Changelog

All notable changes to KadrCaptions will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-04-30

Styled captions → `Kadr.TextOverlay` bridge. The biggest leap of the cycle: a parser path that **preserves** VTT cue settings and inline styling, plus a bridge that maps a styled cue onto kadr v0.8's `TextOverlay` + `textAnimation`. Consumers can now render captions as styled, animated overlays burned into the export — not just `AVMetadataItem` cues for the OS picker.

### Added

- **`StyledCaption`** value type — text + timeRange + alignment + line position + bold / italic / underline flags + speaker + classes. `Sendable`, `Equatable`.
- **`StyledCaptionAlignment`** (`.start` / `.center` / `.end`) and **`StyledCaptionLine`** (`.auto` / `.top` / `.bottom` / `.percent(Double)`).
- **`CaptionParser.parseStyledVTT(_:)`** — pure synchronous string parser. Same WEBVTT-header / NOTE / REGION / STYLE / cue-identifier handling as `parseVTT` but **preserves** cue settings and inline tags as flags / classes / speaker.
- **`Caption.loadStyled(vtt:)`** — async file loader (UTF-8 default, Windows-1252 fallback).
- Pure helpers exposed: `parseStyledVTTTimestampLine`, `parseVTTCueSettings`, `extractStyledRuns`.
- **`StyledCaption.toTextOverlay(baseStyle:animation:)`** — maps a styled cue to `Kadr.TextOverlay` with per-cue `visibilityRange`.
- **`Video.styledCaptions(_:baseStyle:animation:)`** — convenience modifier; overlays an entire array of styled cues. Accumulates across calls.
- Pure mapping helpers exposed for tests: `StyledCaption.mapAlignment`, `applyStyling`, `overlayPosition`, `overlayAnchor`.

### Tag handling

"Any tag of this kind appeared in the cue → per-cue flag set":
- `<i>` / `</i>` → `isItalic`.
- `<b>` / `</b>` → `isBold`.
- `<u>` / `</u>` → `isUnderlined` (recorded; not rendered until `Kadr.TextStyle` grows an underline field).
- `<v Speaker>` → speaker name extracted.
- `<c.foo.bar>` → classnames appended (recorded; v0.3.x `<STYLE>`-block parser will map them to fonts / colors).
- `<00:00:01.500>` timed-text markers stripped.

### Bridge mapping

- `alignment` → `TextStyle.Alignment` (`.start` / `.center` / `.end` → `.leading` / `.center` / `.trailing`).
- `isBold` → `Weight.bold` (preserves `baseStyle.weight` otherwise).
- `isItalic` → `fontName = "Helvetica-Oblique"`. **Documented limitation:** overrides any non-italic font in `baseStyle.fontName`.
- `line == .auto` / `.bottom` → `y = 0.92`, anchor on the bottom row.
- `line == .top` → `y = 0.08`, anchor on the top row.
- `line == .percent(p)` → `y = p / 100`; anchor decided at midline (top half → top anchor, bottom half → bottom anchor).
- Horizontal `position` flows through unchanged; `alignment` picks the matching anchor column (`.start` → left, `.center` → center, `.end` → right).

### Critical contract

The plain-text part of every `StyledCaption` equals what `parseVTT` would produce for the same input. Guarantee verified by a round-trip test.

### Tests

- 57 new tests across `StyledVTTTests` (30) and `StyledCaptionBridgeTests` (27). Coverage: cue setting parsing, inline tag extraction (italic / bold / underline / speaker / classes / timed markers / nested tags), full-document parsing, styled VTT vs. plain VTT plain-text agreement, alignment / weight / italic / position / anchor mapping, `Video.styledCaptions` accumulation, animation passthrough. Suite: 98 → 155.

### Compatibility

- Still requires kadr ≥ 0.9.2 (uses `TextOverlay`, `TextStyle`, `TextAnimation`, `Anchor`, `Position`).
- Pure additive — every v0.2 call site compiles unchanged.

### Notes

- **Mixed inline styling within a cue** is collapsed to per-cue flags. "Half italic, half bold" is recorded as `isItalic = true && isBold = true`; the resulting overlay applies both to the whole cue. Multi-run text is deferred — would need either kadr core to grow a multi-run text type or this package to split a cue into multiple overlays.
- **Styled iTT bridge** is deferred. TTML styling (CSS-style attributes, regions) is a much bigger surface; revisit on demand.
- **`<STYLE>`-block parser** that maps `<c.classname>` to actual styling is deferred to v0.3.x. Classnames are recorded today; no automatic application.

## [0.2.0] - 2026-04-30

iTunes Timed Text (.itt) parser and writer. Completes the "every common subtitle format" story (SRT + VTT + iTT). Pure additive — every v0.1 call site compiles unchanged.

### Added

- **`Caption.load(itt:)`** — async iTT file loader. UTF-8 only (per TTML spec).
- **`CaptionParser.parseITT(_:)`** — pure synchronous string parser. `Foundation.XMLParser`-based; no third-party deps.
- **`CaptionParser.parseITTTime(_:frameRate:)`** — pure helper covering `HH:MM:SS.mmm`, `HH:MM:SS:FF` (frame-count, approximated at the document's declared `ttp:frameRate` or 30 fps fallback), `1.5s`, `1500ms`, plain seconds.
- **`CaptionAuthor.writeITT(_:to:)`** — async iTT file writer (UTF-8, LF, Apple-compatible header).
- **`CaptionAuthor.renderITT(_:)`** — pure render to String.
- **`CaptionAuthor.formatITTTimestamp(_:)`** — pure `HH:MM:SS.mmm` formatter.
- **`CaptionAuthor.renderCueBody(_:)`** — escapes XML entities + converts newlines to `<br/>`.
- **`CaptionAuthor.xmlEscape(_:)`** — five-entity XML escape (`&`, `<`, `>`, `"`, `'`).
- **`CaptionParseError.malformedXML(localizedDescription:)`** — new error case for XML structural failures.

### Changed

- **`Caption.load(_:)`** auto-detect dispatch now recognizes `.itt` (case-insensitive) alongside `.srt` and `.vtt`.

### Cue mapping

- Each `<p>` inside `<body><div>` becomes one `Caption`.
- `<br/>` between text runs becomes `\n`.
- Inline `<span>` styling flattened to plain text. Styled output flows through the v0.3 `TextOverlay` bridge instead.
- Multiple `<div>` blocks concatenate.
- `tt:` prefix on `begin` / `end` attributes tolerated.
- Frame-count timestamps approximated at the document's declared `ttp:frameRate` (with 30 fps fallback) — frame-accurate round-trip is a v0.4+ concern.

### Tests

- 35 new tests covering `parseITTTime` (clock / frame / suffix / plain forms), `parseITT` (minimal docs, `<br/>` line breaks, `<span>` flattening, multi-`<div>`, frame-rate detection, `tt:` prefix tolerance, malformed XML, malformed timestamps), file loaders, the writer + escape helpers, and round-trips through disk. Suite: 63 → 98.

### Notes

- Styled / animated captions (mapping onto kadr v0.8 `TextOverlay` + `textAnimation`) remain deferred to v0.3.0+.
- Frame-rate-aware timing is approximated, not surfaced on `Caption`. Real broadcast iTT files declare drop-frame `frameRate="29.97"`; revisit in a follow-up if accuracy matters.

## [0.1.0] - 2026-04-30

The first release. Parses and writes SubRip (.srt) and WebVTT (.vtt) caption files into kadr's `Caption` value type. Adapter package consuming kadr v0.9.2's caption surface — kadr core ships only the AVFoundation bridge; this package handles the file-format ecosystem.

### Added

- **`Caption.load(_ url: URL)`** — auto-detect by file extension. Dispatches to `load(srt:)` / `load(vtt:)`. Throws `CaptionParseError.unrecognizedFormat` for any other extension.
- **`Caption.load(srt:)`** — async SRT file loader. UTF-8 default with Windows-1252 fallback for legacy files.
- **`Caption.load(vtt:)`** — async WebVTT file loader.
- **`CaptionParser.parseSRT(_:)`** / **`parseVTT(_:)`** — pure synchronous string parsers.
- **`CaptionAuthor.writeSRT(_:to:)`** / **`writeVTT(_:to:)`** — async writers. UTF-8, LF line endings.
- **`CaptionAuthor.renderSRT(_:)`** / **`renderVTT(_:)`** — pure render helpers (string form).
- **`CaptionParseError`** — typed errors with source-line metadata where applicable: `unrecognizedFormat`, `malformedTimestamp`, `malformedCueIndex` (reserved), `missingHeader`, `unreadableFile`, `unsupportedEncoding`.
- Public timestamp helpers: `parseSRTTimestamp` / `parseVTTTimestamp` / `parseSRTTimestampLine` / `parseVTTTimestampLine` / `formatSRTTimestamp` / `formatVTTTimestamp`. Also `stripVTTInlineTags` and `isVTTSkipBlockHeader` for callers needing finer-grained access.

### Real-world tolerance

- CRLF / LF / mixed line endings.
- UTF-8 BOM stripped.
- Lenient SRT cue indexing — non-sequential / missing indices accepted; the parser locates timestamp lines directly.
- Multi-line cues joined with `\n`.
- Dot- and comma-separated milliseconds tolerated in both SRT and VTT.
- Padded / truncated millisecond strings (`5` → 500 ms; `123456` → 123 ms).
- VTT `WEBVTT` header (bare or with description) required; bare missing-header throws `.missingHeader`.
- VTT `NOTE` / `REGION` / `STYLE` blocks tolerated and skipped.
- VTT cue identifiers (string ID before timestamp) ignored.
- VTT cue settings (`align:`, `position:`, `line:`, `region:`) stripped.
- VTT inline tags stripped to plain text: `<c.classname>`, `<i>`/`<b>`/`<u>`, `<v Speaker>`, timed-text markers `<00:00:01.500>`.
- VTT short-form `MM:SS.mmm` timestamps accepted alongside `HH:MM:SS.mmm`.

### Compatibility

- Requires kadr ≥ 0.9.2 (uses `Caption` value type + `Video.captions(_:)`).
- Same platform floor as kadr: iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+, Swift 6.0, strict concurrency.
- No third-party dependencies. Pure Swift + Foundation + CoreMedia.

### Tests

- 63 tests across SRT (26), VTT (31), auto-detect (6) — covering happy paths, real-world edge cases (encodings, line endings, BOM, lenient indexing, padded/truncated ms, dot/comma separators), error paths (malformed timestamps, missing header), tag stripping, and round-trip roundtrips through disk for both formats.

### Notes

- iTT (iTunes Timed Text) parsing is deferred to v0.2.0.
- Styled / animated captions (mapping onto kadr v0.8 `TextOverlay` + `textAnimation`) are deferred to v0.3.0+ once real consumer use cases exist.
- VTT cue settings are dropped in v0.1; revisiting if/when the styled-caption builder lands.
