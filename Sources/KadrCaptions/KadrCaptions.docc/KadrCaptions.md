# ``KadrCaptions``

Caption file parsing and authoring for Kadr — read SRT, VTT, iTT, ASS, SSA,
EBU-TT-D and VobSub, write them back out, and map styled cues onto kadr's
overlay surface for burned-in captions.

## Overview

Kadr core ships only the AVFoundation caption bridge: a `Caption` value type
and `Video.captions(_:)`, which bake cues into an `AVMetadataItem` group at
export. That covers *soft* captions — a track the player can switch on and off.

KadrCaptions handles everything around it: the file-format ecosystem on the way
in, authoring on the way out, and the bridge to burned-in styled captions that
survive re-encoding and upload to platforms with no soft-caption support.

### Reading a caption file

``CaptionParser`` detects the format from the file itself, so a caller that
accepts user-supplied subtitle files does not have to branch on the extension.

```swift
import Kadr
import KadrCaptions

let cues = try CaptionParser.load(url)
let video = Video { clip }.captions(cues)
```

### Styled captions and burn-in

Soft captions cannot carry position, colour or karaoke timing. ``StyledCaption``
preserves what the source format expressed — alignment, regions, per-line runs —
and bridges it onto kadr's `TextOverlay`, so the styling is rendered into the
frames rather than discarded.

This is the path to take when captions must survive a platform that strips
metadata tracks, which in practice is most social video.

### Authoring

``CaptionAuthor`` writes cues back out. Round-tripping is deliberate: a file
parsed and re-authored should express the same timing, and the timestamp
formatters are public so a caller can build format-specific output directly.

## Topics

### Reading

- ``CaptionParser``
- ``CaptionParseError``

### Writing

- ``CaptionAuthor``

### Styled captions

- ``StyledCaption``
- ``StyledCaptionLine``
- ``StyledCaptionAlignment``
- ``CaptionRegion``
- ``RegionScrollMode``

### Bitmap subtitles

- ``VobSubIndex``
- ``VobSubCue``
- ``VobSubBitmap``
