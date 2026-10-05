import Foundation

/// A small, fast, seedable random number generator (SplitMix64).
///
/// Sessions own one of these so their behaviour is reproducible in tests.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// Seeded from the system's random source.
    public init() {
        var system = SystemRandomNumberGenerator()
        state = system.next()
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
