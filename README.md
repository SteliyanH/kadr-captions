# KadrCaptions

[![CI](https://github.com/SteliyanH/kadr-captions/actions/workflows/ci.yml/badge.svg)](https://github.com/SteliyanH/kadr-captions/actions/workflows/ci.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr-captions%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SteliyanH/kadr-captions)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr-captions%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SteliyanH/kadr-captions)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/steliyanh)

**Caption parsing and burn-in for [Kadr](https://github.com/SteliyanH/kadr) — read SRT / VTT / iTT / ASS / SSA / VobSub, write them back, and burn styled cues into the video itself.**

**[API documentation →](https://swiftpackageindex.com/SteliyanH/kadr-captions/documentation)**  ·  built and hosted by the Swift Package Index for every release.

KadrCaptions consumes kadr's `Caption` value type and `Video.captions(_:)` modifier. Core kadr ships only the AVFoundation bridge (caption → `AVMetadataItem` at export). This adapter handles the file-format ecosystem.

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
| `CaptionParser.extractVobSubBitmaps(idx:sub:)` *(v0.7)* | Async `[VobSubBitmap]` — RLE-decoded SPU bitmaps for iPhone-era DVD subtitle pairs |
| `Caption.split(at:)` *(v0.7)* | Cleave a cue at an absolute timestamp into a pair |
| `Caption.snappedToFrameRate(_:)` *(v0.7)* | Round cue boundaries to the nearest frame (23.976 / 24 / 25 / 29.97 / 30 / 60) |
| `Array<Caption>.merged(within:)` *(v0.7)* | Collapse adjacent / overlapping cues whose gap is ≤ threshold (newline-joined text) |
| `CaptionParseError` | Typed errors with source-line metadata |

## Why a separate package?

kadr core stays AVFoundation-bridge-only — small, no third-party deps, predictable surface. Caption file parsing has real-world variance (encodings, malformed timestamps, VTT cue settings, inline styles, iTT XML) that doesn't earn a slot in core. Reading and writing the same format are dual operations and live together in this adapter.

## Roadmap

See [ROADMAP.md](ROADMAP.md). Shipped: SRT + VTT (v0.1.0), iTT (v0.2.0), styled VTT → `TextOverlay` bridge (v0.3.0), ASS / SSA (v0.4.0), styled ASS / SSA + caption time utilities (v0.5.0), VobSub `.idx` + WebVTT cue regions + EBU-TT-D (v0.6.0), VobSub `.sub` SPU bitmap extraction + caption merge / split / frame-snap utilities (v0.7.0), iOS 17 platform floor (v0.8.0), DocC catalogue + `.upToNextMinor` pinning (v0.8.1), `LocalizedError` conformance (v0.9.0), kadr 0.17 adoption (v0.10.0). Covers every common subtitle format with plain-text + (where applicable) styled support, plus DVD-era image-based subtitles end-to-end and European broadcast TTML.

## Installation

```swift
.package(url: "https://github.com/SteliyanH/kadr-captions.git", .upToNextMinor(from: "0.12.0")),
```

Add `KadrCaptions` to your target's dependencies. `Kadr` is pulled in transitively — 0.10.x resolves `>=0.17.0, <0.18.0`.

> **Use `.upToNextMinor`, not `from:`.** `from:` means `.upToNextMajor`, and SwiftPM does not special-case `0.x` — so `from: "0.12.0"` would accept every future 0.x release including breaking ones. This package's own kadr dependency is pinned the same way, because kadr's minors do break: 0.15.0 raised the platform floor.

## Burn-in

Soft captions are metadata: a player can switch them off, and most platforms strip them on re-encode. Burned-in captions are pixels, and they survive anywhere the video goes — which is what social video needs.

`StyledCaption` renders through kadr's `TextOverlay`, so a styled cue becomes part of the composition:

```swift
let cues = try await Caption.loadStyled(vtt: vttURL)

let video = Video {
    VideoClip(url: footage)
}
.styledCaptions(cues, animation: .fadeIn(duration: 0.3))
```

Colour, bold, italic, alignment and WebVTT position / anchor semantics all carry through, and each cue is visible only for its own time range.

**Known limits.** Karaoke tags, `\pos(...)` and font / size overrides are stripped, because `TextStyle` cannot render them. Cue timing is taken from the caption file, which is relative to the source asset — trimming a clip or applying a speed curve will drift the captions against the composition timeline.

## Requirements

Swift 6 · iOS 17 · macOS 14 · tvOS 17 · visionOS 1 · kadr 1.0+

## The kadr ecosystem

| Package | Purpose |
|---|---|
| [`kadr`](https://github.com/SteliyanH/kadr) | The engine. Declarative video composition and export. |
| [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) | SwiftUI components — preview, timeline, transport, inspector, keyframe editor. |
| [`kadr-persistence`](https://github.com/SteliyanH/kadr-persistence) | Save a composition to a file and open it again. |
| [`kadr-audio`](https://github.com/SteliyanH/kadr-audio) | Music library, voiceover recording, LUFS loudness. |
| [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) | SRT, VTT, iTT, ASS and SSA parsing and authoring. |
| [`kadr-photos`](https://github.com/SteliyanH/kadr-photos) | Photos library integration. |

And a reference application: [**Kadr Studio**](https://github.com/SteliyanH/kadr-reels-studio), a short-form vertical video editor built on all six.

## License

Apache-2.0. See [LICENSE](LICENSE).

Contributions are accepted under the [Contributor License Agreement](CLA.md), which is signed once and covers all future contributions. It does not transfer ownership — you keep the copyright in your work.
