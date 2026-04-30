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

## v0.4.0 — ASS / SSA *(planned)*

Advanced SubStation Alpha — used heavily in anime / fansub pipelines. Adds the fourth and final common caption format.

## Compatibility track record

| KadrCaptions | Requires Kadr |
|---|---|
| 0.1.0 | ≥ 0.9.2 |
| 0.2.0 | ≥ 0.9.2 |
| 0.3.0 | ≥ 0.9.2 |
| 0.4.0+ *(planned)* | ≥ 0.9.2 |

## Contributing

Open an issue on this repo for parsing edge cases, or on [kadr](https://github.com/SteliyanH/kadr) for upstream caption-surface requests.
