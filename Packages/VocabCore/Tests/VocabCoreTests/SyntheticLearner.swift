import Foundation

@testable import VocabCore

/// A made-up learner whose memory follows FSRS with known parameters, for testing the
/// optimizer. Intervals vary widely around the true stability so the reviews carry
/// information about the forgetting curve.
struct SyntheticLearner {
    /// The review history of one card: its first study day and each review's grade
    /// with the study days since the previous review.
    struct History: Codable, Equatable {
        var day: Int
        var reviews: [[Int]]
    }

    var parameters: FSRSParameters
    var random: SeededRandom

    init(parameters: FSRSParameters = .default, seed: UInt64) {
        self.parameters = parameters
        random = SeededRandom(seed: seed)
    }

    /// Learner parameters that differ clearly from the defaults.
    static let unusual: FSRSParameters = {
        var w = FSRSParameters.default.weights
        w[0] = 0.5
        w[1] = 2.5
        w[2] = 5
        w[3] = 15
        w[8] = 1.4
        w[9] = 0.3
        w[10] = 1.2
        w[11] = 1.0
        w[16] = 2.5
        w[20] = 0.3
        return FSRSParameters(w)!
    }()

    mutating func histories(cards: Int, days: Int) -> [History] {
        let fsrs = FSRS(parameters: parameters)
        return (0..<cards).map { _ in
            let start = Int.random(in: 0..<(days / 2), using: &random)
            var reviews: [[Int]] = []
            var memory: FSRS.Memory?
            func review(_ grade: Grade, after elapsed: Int) {
                memory = fsrs.review(memory, elapsedDays: elapsed, grade: grade)
                reviews.append([grade.rawValue, elapsed])
            }

            review(firstGrade(), after: 0)
            relearn(review)
            var day = start
            while true {
                let interval = max(1, Int((memory!.stability * Double.random(in: 0.3...3, using: &random)).rounded()))
                day += interval
                guard day < days else { break }
                let recall = fsrs.retrievability(elapsedDays: Double(interval), stability: memory!.stability)
                if Double.random(in: 0..<1, using: &random) < recall {
                    review(recalledGrade(), after: interval)
                } else {
                    review(.again, after: interval)
                    relearn(review)
                }
            }
            return History(day: start, reviews: reviews)
        }
    }

    /// Same-day reviews until two Goods in a row, like the steps of a session.
    private mutating func relearn(_ review: (Grade, Int) -> Void) {
        var steps = 0
        while steps < 2 {
            let good = Double.random(in: 0..<1, using: &random) < 0.8
            review(good ? .good : .again, 0)
            steps = good ? steps + 1 : 0
        }
    }

    private mutating func firstGrade() -> Grade {
        let x = Double.random(in: 0..<1, using: &random)
        return x < 0.25 ? .again : x < 0.4 ? .hard : x < 0.9 ? .good : .easy
    }

    private mutating func recalledGrade() -> Grade {
        let x = Double.random(in: 0..<1, using: &random)
        return x < 0.15 ? .hard : x < 0.85 ? .good : .easy
    }
}

extension SyntheticLearner.History {
    /// A card with this history, reviewed at distinct times so the order of items is
    /// fixed: by study day, then by `index`.
    func card(index: Int, calendar: StudyCalendar) -> Card {
        var day = self.day
        var log: [ReviewLogEntry] = []
        for (position, review) in reviews.enumerated() {
            day += review[1]
            let date = calendar.start(ofDay: day).addingTimeInterval(3600 + Double(index) + Double(position) * 0.001)
            log.append(ReviewLogEntry(date: date, grade: Grade(rawValue: review[0])!))
        }
        let state = LearningState(
            phase: .review, stability: 1, difficulty: 5,
            lastReview: log.last!.date, due: log.last!.date, reviews: log.count
        )
        return Card(question: "q\(index)", answer: "a\(index)", learningState: state, log: log)
    }
}
