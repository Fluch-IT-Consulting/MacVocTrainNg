import Foundation

extension DeckChange {
    /// Merges `other`, another version of the same deck, into `deck`, e.g. a version
    /// iCloud Drive kept apart after a conflict; `nil` if `deck` holds all of it already.
    ///
    /// - The content (cards with their texts, their order, the learning options) comes
    ///   from the version with the later `contentModified`, or from `deck` if they are
    ///   the same. Only the Mac changes the content; a card the content doesn't hold
    ///   any more drops out with its reviews.
    /// - The review logs of a card are joined. A review in both versions, at the same
    ///   second with the same grade, counts once.
    /// - The learning state of a card comes from the version that holds all its
    ///   reviews, replayed with the parameters of the content if they differ there
    ///   (`Scheduler.replayingMemory(of:)`). If each version has reviews the other
    ///   lacks, the joined log is replayed from scratch (`Scheduler.replaying(_:of:)`);
    ///   if it doesn't reach back to the first review, see `continuing`.
    /// - The progress joins the days of both versions; a day in both comes from the
    ///   one with more days. Applying the change records the snapshot of its day anew.
    ///
    /// Merging `deck` into `other` gives the same deck, but for the fractions of a
    /// second of reviews both versions hold (`reviews.jsonl` keeps whole seconds), and
    /// for the content if both versions have the same `contentModified` but different
    /// content. That happens only to versions last changed by an app version without
    /// `contentModified`.
    ///
    /// - Parameter calendar: Counts study days for replaying, and should be the one
    ///   other devices use, so they all replay a log to the same learning state.
    public static func merging(_ other: Deck, into deck: Deck, calendar: StudyCalendar) -> DeckChange? {
        let otherHasContent = (other.contentModified ?? .distantPast) > (deck.contentModified ?? .distantPast)
        let content = otherHasContent ? other : deck
        let scheduler = Scheduler(learningOptions: content.learningOptions, calendar: calendar)
        let mine = Dictionary(deck.cards.map { ($0.id, $0) }) { first, _ in first }
        let theirs = Dictionary(other.cards.map { ($0.id, $0) }) { first, _ in first }

        var change = DeckChange(contentStamp: .keep)
        for (index, card) in content.cards.enumerated() {
            var merged = card
            if let mine = mine[card.id], let theirs = theirs[card.id] {
                let learned = learning(
                    of: Version(card: mine, parameters: deck.learningOptions.parameters, hasContent: !otherHasContent),
                    and: Version(card: theirs, parameters: other.learningOptions.parameters, hasContent: otherHasContent),
                    scheduler: scheduler
                )
                merged.learningState = learned.learningState
                merged.log = learned.log
            }
            if let existing = mine[card.id] {
                if merged != existing { change.upserts.append((merged, nil)) }
            } else {
                // At its index in the content, so the cards end up in its order.
                change.upserts.append((merged, index))
            }
        }
        let kept = Set(content.cards.map(\.id))
        change.removals = deck.cards.map(\.id).filter { !kept.contains($0) }

        if content.learningOptions != deck.learningOptions {
            change.learningOptions = content.learningOptions
        }
        if content.contentModified != deck.contentModified {
            change.contentStamp = .set(content.contentModified)
        }
        let progress = joinedProgress(deck.progress, other.progress, preferringFirst: !otherHasContent)
        if progress != deck.progress {
            change.progress = progress
        }

        if case .keep = change.contentStamp, change.upserts.isEmpty, change.removals.isEmpty, change.learningOptions == nil, change.progress == nil {
            return nil
        }
        return change
    }

    /// One version of a card in a merge.
    private struct Version {
        var card: Card
        /// The parameters its learning state was computed with.
        var parameters: FSRSParameters
        /// Whether its deck is the one the merge takes the content from.
        var hasContent: Bool
    }

    /// A review as a merge compares it: at whole seconds, as `reviews.jsonl` stores it.
    private struct ReviewKey: Hashable {
        var second: Int
        var grade: Grade

        init(_ entry: ReviewLogEntry) {
            second = Int(entry.date.timeIntervalSince1970.rounded(.down))
            grade = entry.grade
        }
    }

    /// The reviews of `log` that `others` lacks; a review in both counts once, but
    /// twice if one of them holds it twice.
    private static func reviews(of log: [ReviewLogEntry], missingFrom others: [ReviewLogEntry]) -> [ReviewLogEntry] {
        var remaining: [ReviewKey: Int] = [:]
        for entry in others {
            remaining[ReviewKey(entry), default: 0] += 1
        }
        return log.filter { entry in
            let key = ReviewKey(entry)
            guard let count = remaining[key], count > 0 else { return true }
            remaining[key] = count - 1
            return false
        }
    }

    /// The card of one of both versions, with the learning state and review log the
    /// merge gives it; its other properties don't count.
    private static func learning(of mine: Version, and theirs: Version, scheduler: Scheduler) -> Card {
        let onlyMine = reviews(of: mine.card.log, missingFrom: theirs.card.log)
        let onlyTheirs = reviews(of: theirs.card.log, missingFrom: mine.card.log)

        if onlyMine.isEmpty || onlyTheirs.isEmpty {
            // One version holds every review; with the same reviews, the content's.
            let complete: Version
            if onlyMine.isEmpty && onlyTheirs.isEmpty {
                complete = mine.hasContent ? mine : theirs
            } else {
                complete = onlyTheirs.isEmpty ? mine : theirs
            }
            guard complete.parameters != scheduler.learningOptions.parameters else { return complete.card }
            return scheduler.replayingMemory(of: complete.card) ?? complete.card
        }

        let joined = (mine.card.log + onlyTheirs).sorted { ($0.date, $0.grade) < ($1.date, $1.grade) }
        if mine.card.hasCompleteLog && theirs.card.hasCompleteLog {
            return scheduler.replaying(joined, of: mine.card)
        }
        return continuing(mine, theirs, scheduler: scheduler)
    }

    /// For logs that don't reach back to the first review, as after an import from
    /// MacVocTrain 1: continues the version whose last review is the earlier one with
    /// the reviews only the other holds (`Scheduler.review`). A review before the last
    /// one of the continued version only joins its log.
    private static func continuing(_ mine: Version, _ theirs: Version, scheduler: Scheduler) -> Card {
        let lastMine = mine.card.learningState?.lastReview ?? .distantPast
        let lastTheirs = theirs.card.learningState?.lastReview ?? .distantPast
        let mineFirst = lastMine < lastTheirs || (lastMine == lastTheirs && mine.hasContent)
        let (earlier, later) = mineFirst ? (mine.card, theirs.card) : (theirs.card, mine.card)

        var card = earlier
        let added = reviews(of: later.log, missingFrom: earlier.log).sorted { ($0.date, $0.grade) < ($1.date, $1.grade) }
        for entry in added {
            if var learningState = card.learningState, entry.date <= learningState.lastReview {
                // Counted, so the log stays no longer than the reviews (see `DeckFile`).
                learningState.reviews += 1
                card.learningState = learningState
                let index = card.log.firstIndex { $0.date > entry.date } ?? card.log.endIndex
                card.log.insert(entry, at: index)
            } else {
                var random = Scheduler.random(forReviewOf: card.id, at: entry.date)
                card = scheduler.review(card, grade: entry.grade, at: entry.date, mode: entry.mode, using: &random)
            }
        }
        return card
    }

    /// The snapshots of both progresses by day, those of `first` for a day in both if
    /// it has more days or, with as many, if `preferringFirst`.
    private static func joinedProgress(_ first: [DailySnapshot], _ second: [DailySnapshot], preferringFirst: Bool) -> [DailySnapshot] {
        let firstWins = first.count > second.count || (first.count == second.count && preferringFirst)
        let (winner, other) = firstWins ? (first, second) : (second, first)
        var snapshots = Dictionary(other.map { ($0.day, $0) }) { _, last in last }
        for snapshot in winner {
            snapshots[snapshot.day] = snapshot
        }
        return snapshots.values.sorted { $0.day < $1.day }
    }
}
