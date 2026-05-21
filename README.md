# KadrCaptions

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016+%20|%20macOS%2013+%20|%20tvOS%2016+%20|%20visionOS%201+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

**Caption file parsing and authoring for [Kadr](https://github.com/SteliyanH/kadr) — produce `Caption` values from SRT / VTT / iTT files, write them back, and (later) map styled cues onto kadr's `TextOverlay` surface.**

KadrCaptions consumes kadr v0.9.2's `Caption` value type and `Video.captions(_:)` modifier. Core kadr ships only the AVFoundation bridge (caption → `AVMetadataItem` at export). This adapter handles the file-format ecosystem.

## Quick Start

```swift
import Kadr
import KadrCaptions

// Auto-detect by extension (.srt / .vtt)
let cues = try await Caption.load(subtitleURL)

let video = Video {
    VideoClip(url: footage)
}
.captions(cues)

try await video.export(to: outputURL)  // captions baked as AVMetadataItem at export

// Or write captions back to disk:
try await CaptionAuthor.writeSRT(cues, to: outputSRT)
try await CaptionAuthor.writeVTT(cues, to: outputVTT)
```

## API

| Surface | Purpose |
|---|---|
| `Caption.load(_ url:)` | Auto-detect by extension; dispatches to `load(srt:)` / `load(vtt:)` / `load(itt:)` / `load(ass:)` / `load(ssa:)` |
| `Caption.load(srt:)` / `load(vtt:)` / `load(itt:)` / `load(ass:)` / `load(ssa:)` *(v0.4)* | Async file loaders; SRT / ASS / SSA loaders have UTF-8 + Windows-1252 fallback |
| `Caption.loadStyled(vtt:)` *(v0.3)* | Async loader producing `StyledCaption` (preserves cue settings + inline tags) |
| `CaptionParser.parseSRT(_:)` / `parseVTT(_:)` / `parseITT(_:)` / `parseASS(_:)` / `parseSSA(_:)` *(v0.4)* | Pure synchronous string parsers |
| `CaptionParser.parseStyledVTT(_:)` *(v0.3)* | Styled VTT parser — preserves alignment / line / position / bold / italic / speaker / classes |
| `CaptionAuthor.writeSRT(_:to:)` / `writeVTT(_:to:)` / `writeITT(_:to:)` / `writeASS(_:to:)` / `writeSSA(_:to:)` *(v0.4)* | Async writers (UTF-8, LF) |
| `CaptionAuthor.renderSRT(_:)` / `renderVTT(_:)` / `renderITT(_:)` / `renderASS(_:)` / `renderSSA(_:)` *(v0.4)* | Pure render helpers (string form) |
| `StyledCaption.toTextOverlay(baseStyle:animation:)` *(v0.3)* | Bridge to `Kadr.TextOverlay` for burned-in styled captions |
| `Video.styledCaptions(_:baseStyle:animation:)` *(v0.3)* | Overlay every styled cue with per-cue visibility |
| `CaptionParseError` | Typed errors with source-line metadata |

## Why a separate package?

kadr core stays AVFoundation-bridge-only — small, no third-party deps, predictable surface. Caption file parsing has real-world variance (encodings, malformed timestamps, VTT cue settings, inline styles, iTT XML) that doesn't earn a slot in core. Reading and writing the same format are dual operations and live together in this adapter.

## Roadmap

See [ROADMAP.md](ROADMAP.md). Shipped: SRT + VTT (v0.1.0), iTT (v0.2.0), styled VTT → `TextOverlay` bridge (v0.3.0), ASS / SSA (v0.4.0), styled ASS / SSA + caption time utilities (v0.5.0), VobSub `.idx` + WebVTT cue regions + EBU-TT-D (v0.6.0). Covers every common subtitle format with plain-text + (where applicable) styled support, plus DVD-era image-based subtitles and European broadcast TTML.

## Installation

```swift
.package(url: "https://github.com/SteliyanH/kadr-captions.git", from: "0.5.0"),
```

Add `KadrCaptions` to your target's dependencies. `Kadr` is pulled in transitively (≥ `0.9.2`).

## License

Apache-2.0. See [LICENSE](LICENSE).
