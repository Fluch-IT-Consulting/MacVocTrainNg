import Combine
import Foundation
import Observation

/// The number of cards due now, for the toolbar, the menu, the session summary and
/// the status bar of the card list.
///
/// Counts again after every change to the deck and at the start of every minute,
/// because cards become due as time passes. The minute is the one of
/// `TimelineView(.everyMinute)`, so the number changes together with the due dates
/// the views show. Observers hear of it only when the number changes, so a window
/// that shows it isn't redrawn every minute.
@MainActor @Observable
final class DueCardCounter {
    private(set) var count: Int
    /// The document owns the counter.
    @ObservationIgnored private unowned let document: VocabularyDocument
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []

    init(document: VocabularyDocument) {
        self.document = document
        count = document.deck.dueCount(at: document.clock.now)
        document.deckDidChange
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        scheduleRefresh()
    }

    /// Counts the due cards at the time of the document's clock.
    func refresh() {
        let count = document.deck.dueCount(at: document.clock.now)
        if count != self.count {
            self.count = count
        }
    }

    /// The start of the minute after `date`. Every time zone is a whole number of
    /// minutes off UTC, so this is the full minute on the clock as well.
    nonisolated static func nextRefresh(after date: Date) -> Date {
        let minutes = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) + 1
        return Date(timeIntervalSinceReferenceDate: minutes * 60)
    }

    /// Refreshes at the next full minute and schedules the one after. A timer that
    /// repeats every 60 seconds would tick at the second the document was opened.
    ///
    /// The timer runs in real time, not on the document's clock, which a test may
    /// hold still. Once the counter is gone, the last timer fires without effect.
    private func scheduleRefresh() {
        let timer = Timer(fire: Self.nextRefresh(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.scheduleRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
