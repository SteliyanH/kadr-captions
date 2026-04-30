# Changelog

All notable changes to KadrCaptions will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
