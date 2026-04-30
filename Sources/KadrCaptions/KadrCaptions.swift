import Kadr

/// KadrCaptions — caption file parsing and authoring for kadr.
///
/// See [DESIGN.md](https://github.com/SteliyanH/kadr-captions/blob/main/DESIGN.md) for
/// the v0.1 RFC. Public API lands in subsequent tier PRs (SRT parser → SRT writer →
/// VTT parser → VTT writer → auto-detect → release).
///
/// This module re-exports kadr's ``Kadr/Caption`` and ``Kadr/Video/captions(_:)`` so
/// downstream consumers can `import KadrCaptions` without also importing `Kadr`
/// directly when they only need captions.
public typealias Caption = Kadr.Caption
