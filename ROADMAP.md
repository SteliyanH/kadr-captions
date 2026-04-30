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

## v0.2.0 — iTT *(planned)*

iTunes Timed Text (.itt) parser and writer. Verbose XML; larger surface than SRT/VTT.

- `Caption.load(itt: URL) async throws -> [Caption]`
- `CaptionAuthor.writeITT(_:to:) async throws`

## v0.3.0+ — Styled / animated captions *(planned)*

Bridges a styled VTT cue (or programmatic builder) onto kadr v0.8's `TextOverlay` + `textAnimation`. Lets consumers ingest a styled caption file and render it as an animated overlay rather than a plain metadata cue. Surface design TBD; depends on real consumer use cases.

## Compatibility track record

| KadrCaptions | Requires Kadr |
|---|---|
| 0.1.0 | ≥ 0.9.2 |
| 0.2.0+ *(planned)* | ≥ 0.9.2 |

## Contributing

Open an issue on this repo for parsing edge cases, or on [kadr](https://github.com/SteliyanH/kadr) for upstream caption-surface requests.
