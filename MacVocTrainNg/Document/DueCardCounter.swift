import Combine
import Foundation
import Observation

/// The number of cards due now, for the toolbar, the menu and the session summary.
///
/// Counts again after every change to the deck and once a minute, because cards become
/// due as time passes. Observers hear of it only when the number changes, so a window
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
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    /// Counts the due cards at the time of the document's clock.
    func refresh() {
        let count = document.deck.dueCount(at: document.clock.now)
        if count != self.count {
            self.count = count
        }
    }
}
