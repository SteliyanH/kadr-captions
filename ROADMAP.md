# KadrCaptions Roadmap

This document outlines the planned feature releases for KadrCaptions. Each release is gated on the matching [kadr](https://github.com/SteliyanH/kadr) public surface.

For kadr's roadmap see [kadr/ROADMAP.md](https://github.com/SteliyanH/kadr/blob/main/ROADMAP.md).

## v0.1.0 — SRT + VTT ✓ shipped

The first release. Parses and writes SubRip (.srt) and WebVTT (.vtt) caption files into kadr's `Caption` value type.

- `Caption.load(srt: URL) async throws -> [Caption]` — SRT parser
- `Caption.load(vtt: URL) async throws -> [Caption]` — VTT parser (plain text mode; cue settings + inline styles stripped)
- `Caption.load(_ url: URL) async throws -> [Caption]` — auto-detect format by extension
- `CaptionAuthor.writeSRT(_:to:) async throws` — SRT writer
- `CaptionAuthor.writeVTT(_:to:) async throws` — VTT writer
- UTF-8 default with Windows-1252 fallback for legacy SRT files
- CRLF / LF / mixed line endings
- Multi-line cues, malformed-timestamp errors, BOM handling

Depends on **kadr v0.9.2** (uses `Caption` value type + `Video.captions(_:)`).

## v0.2.0 — iTT ✓ shipped

iTunes Timed Text (.itt) parser and writer. `Foundation.XMLParser`-based; no third-party deps. Plain-text Caption mapping (styled regions / spans flattened); the v0.3 `TextOverlay` bridge handles the visual side.

- `Caption.load(itt:)` + `CaptionParser.parseITT(_:)` + `parseITTTime(_:frameRate:)`
- `CaptionAuthor.writeITT(_:to:)` + `renderITT(_:)` + `formatITTTimestamp(_:)`
- `Caption.load(_:)` auto-detect extended for `.itt`
- New `CaptionParseError.malformedXML(localizedDescription:)`

## v0.3.0 — Styled captions → TextOverlay ✓ shipped

Bridges a styled VTT cue (or programmatic builder) onto kadr v0.8's `TextOverlay` + `textAnimation`. Consumers ingest a styled caption file and render it as a styled / animated overlay burned into the export.

- `StyledCaption` value type + `StyledCaptionAlignment` / `StyledCaptionLine` enums
- `CaptionParser.parseStyledVTT(_:)` + `Caption.loadStyled(vtt:)`
- `StyledCaption.toTextOverlay(baseStyle:animation:)` bridge
- `Video.styledCaptions(_:baseStyle:animation:)` convenience modifier

## v0.4.0 — ASS / SSA ✓ shipped

Advanced SubStation Alpha (.ass) and SubStation Alpha (.ssa). Plain-text Caption mapping (style overrides + karaoke tags stripped); the v0.3 `TextOverlay` bridge handles the visual side if needed. **Completes the every-common-format matrix.**

- `CaptionParser.parseASS(_:)` / `parseSSA(_:)` + `Caption.load(ass:)` / `load(ssa:)`
- `CaptionAuthor.writeASS(_:to:)` / `writeSSA(_:to:)` + `renderASS(_:)` / `renderSSA(_:)`
- Pure helpers: `parseASSTimestamp`, `formatASSTimestamp`, `splitASSDialogue`, `stripASSOverrides`
- `Caption.load(_:)` auto-detect extended for `.ass` / `.ssa`

## v0.5.0 — Styled ASS / SSA + time utilities ✓ shipped

Closes the high-value gaps from a final feature audit. Pure additive — every v0.4 call site compiles unchanged.

- **`Caption.shifted(by:)` / `Caption.scaled(by:)`** — pure value-type transforms for syncing cues to a re-encoded / sped-up video. Array sugar mirrors both.
- **`CaptionParser.parseStyledASS(_:)` / `parseStyledSSA(_:)`** + **`Caption.loadStyled(ass:)` / `loadStyled(ssa:)`** — round-trip color, bold / italic / underline, and alignment (`\an<N>` numpad + legacy `\a<N>` SSA bitmask) into `[StyledCaption]`. ASS alpha flipped on import.
- **`StyledCaption.color: String?`** — hex-form color field with `nil` default; bridge applies via the new `StyledCaption.platformColor(forHex:)` helper. Karaoke tags / `\pos(...)` / font / size overrides remain stripped (TextStyle can't render them).

Cycle considered feature-complete pending kadr v1.0.

## v0.6.0 — Format extensions ✓ shipped

Reopened cycle (v0.5 was marked feature-complete) to close niche-but-real ingest gaps. Three additions, all additive — every v0.5 call site compiles unchanged.

- **VobSub `.idx` parser** — `VobSubIndex` + `VobSubCue` types + `parseVobSubIndex` + `Caption.fromVobSubIndex(_:)` bridge. Index timing + palette + filepos surfaced; bitmap extraction deferred to v0.7.
- **WebVTT cue regions** — `CaptionRegion` + `RegionScrollMode` types; `StyledCaption.region: CaptionRegion?` field; `parseStyledVTT` resolves `region:NAME` cue references against REGION blocks declared in the file. Plain `parseVTT` stays cleanly stripped.
- **EBU-TT-D parser** — `parseEBUTTD(_:)` + `Caption.load(ebuTTD:)` for the European broadcast TTML profile. Strict clock-form timing (rejects iTT frame-count + TTML suffix forms). Plain text only.

39 new tests across the cycle. XCTest suite 43 → 82. Pure ingest expansion — no upstream changes needed.

## Compatibility track record

| KadrCaptions | Requires Kadr |
|---|---|
| 0.1.0 | ≥ 0.9.2 |
| 0.2.0 | ≥ 0.9.2 |
| 0.3.0 | ≥ 0.9.2 |
| 0.4.0 | ≥ 0.9.2 |
| 0.5.0 | ≥ 0.9.2 |
| 0.6.0 | ≥ 0.9.2 |
| 0.7.0 | ≥ 0.9.2 |

## v0.7.0 — VobSub bitmap extraction + caption-utility helpers ✓ shipped

Reopened cycle. v0.6 surfaced the `.idx` half of VobSub (timing + palette + filepos) but explicitly punted the `.sub` bitmap decode to v0.7. This cycle closes that gap and bundles a small set of caption-utility helpers that have come up downstream as one-liners consumers keep reimplementing. Pure additive — every v0.6 call site compiles unchanged. Two tiers:

- **VobSub `.sub` SPU bitmap extraction.** New `extractVobSubBitmaps(idx:sub:)` async helper decodes the run-length-encoded subpicture units (SPUs) referenced by `VobSubCue.fileOffset` and returns a `[VobSubBitmap]` — each entry pairs the cue timing with a `CGImage` rendered from the SPU's 2-bit indexed pixels through the `.idx` palette. `VobSubBitmap` also carries the SPU's control-sequence `end: CMTime` (display duration), which the `.idx` alone can't tell you. Free per the locked premium scope — bitmap decode is pure parser work; AI / OCR stays out.
- **Caption-utility helpers.** Pure value-type transforms in the same shape as v0.5's `shifted(by:)` / `scaled(by:)`. Three additions: `Caption.merged(within:)` collapses adjacent cues whose gap is below a threshold; `Caption.split(at:)` cleaves one cue into two at a given offset; `Caption.snappedToFrameRate(_:)` rounds start / end to the nearest frame boundary for export-friendly timing. Array sugar mirrors each.

Two tiers + release prep. Pure ingest + utility expansion — nothing changes for consumers who only need the v0.6 happy path.

## Contributing

Open an issue on this repo for parsing edge cases, or on [kadr](https://github.com/SteliyanH/kadr) for upstream caption-surface requests.
