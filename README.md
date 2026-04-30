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
| `Caption.load(_ url:)` | Auto-detect by extension; dispatches to `load(srt:)` / `load(vtt:)` |
| `Caption.load(srt:)` / `load(vtt:)` | Async file loaders; UTF-8 default with Windows-1252 fallback |
| `CaptionParser.parseSRT(_:)` / `parseVTT(_:)` | Pure synchronous string parsers |
| `CaptionAuthor.writeSRT(_:to:)` / `writeVTT(_:to:)` | Async writers (UTF-8, LF) |
| `CaptionAuthor.renderSRT(_:)` / `renderVTT(_:)` | Pure render helpers (string form) |
| `CaptionParseError` | Typed errors with source-line metadata |

## Why a separate package?

kadr core stays AVFoundation-bridge-only — small, no third-party deps, predictable surface. Caption file parsing has real-world variance (encodings, malformed timestamps, VTT cue settings, inline styles, iTT XML) that doesn't earn a slot in core. Reading and writing the same format are dual operations and live together in this adapter.

## Roadmap

See [ROADMAP.md](ROADMAP.md). v0.1.0 scope: SRT + VTT parsers and writers. iTT planned for v0.2.0. Styled-caption builder (TextOverlay mapping) for v0.3.0+.

## Installation

```swift
.package(url: "https://github.com/SteliyanH/kadr-captions.git", from: "0.1.0"),
```

Add `KadrCaptions` to your target's dependencies. `Kadr` is pulled in transitively (≥ `0.9.2`).

## License

Apache-2.0. See [LICENSE](LICENSE).
