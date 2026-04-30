import Testing
@testable import KadrCaptions

/// Placeholder for the v0.1 cycle. Real tests land alongside SRT / VTT parsers in
/// subsequent tier PRs.
struct KadrCaptionsTests {

    @Test func moduleBuilds() {
        // If this file compiles, KadrCaptions imported Kadr correctly and the
        // Caption typealias resolves.
        let _: Caption.Type = Caption.self
    }
}
