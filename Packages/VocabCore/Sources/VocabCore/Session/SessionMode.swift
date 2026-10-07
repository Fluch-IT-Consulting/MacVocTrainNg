import Foundation

/// A command that every mode passes on to its `Session` unchanged.
public enum SessionCommand: Sendable {
    /// Stops introducing new cards; only cards already asked are finished.
    case finishUp
    /// Drops the current card without recording a review, e.g. because it was deleted.
    case skip
}

/// A way to run a `Session`: `StudySession` or `Practice`. The mode decides how a
/// review is recorded; it alone changes its session.
public protocol SessionMode: Sendable {
    var session: Session { get }
    /// Carries out `command` on `session`.
    mutating func perform(_ command: SessionCommand)
}
