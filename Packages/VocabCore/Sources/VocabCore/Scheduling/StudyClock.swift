import Foundation

/// Where the current time comes from.
///
/// Code outside the core that reviews cards or picks due cards asks a clock instead of
/// calling `Date()`, so tests can move time forward, e.g. across the start of a study day.
public struct StudyClock: Sendable {
    private let read: @Sendable () -> Date

    public init(_ now: @escaping @Sendable () -> Date) {
        read = now
    }

    /// The system time.
    public static let system = StudyClock { Date() }

    public var now: Date { read() }
}
