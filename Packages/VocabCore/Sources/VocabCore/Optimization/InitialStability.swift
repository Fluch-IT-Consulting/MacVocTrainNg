import Foundation

/// Fits the initial stabilities w0–w3 before training. Port of
/// `parameter_initialization.rs` in fsrs-rs 6.6.2.
///
/// For each grade of a card's first review, it searches the stability whose
/// forgetting curve best explains whether the card was recalled at its first review
/// on a later study day.
enum InitialStability {
    static let maximum = 100.0

    struct Result {
        var stabilities: [Double]
        /// Items per grade of the first review that went into the fit.
        var counts: [Grade: Int]
    }

    /// - Parameters:
    ///   - items: Items with exactly one review on a later study day.
    ///   - averageRecall: Share of recalled targets in the training set, for smoothing.
    static func fit(_ items: [TrainingItem], averageRecall: Double) -> Result? {
        // first grade -> elapsed days of the first long-term review -> recalled per item
        var groups: [Grade: [Int: [Bool]]] = [:]
        for item in items where item.longTermReviewCount == 1 {
            guard let review = item.firstLongTermReview else { continue }
            groups[item.reviews[0].grade, default: [:]][review.elapsedDays, default: []].append(review.grade.isRecall)
        }

        var stabilities: [Grade: Double] = [:]
        var counts: [Grade: Int] = [:]
        for (grade, byDays) in groups {
            let points = byDays.sorted { $0.key < $1.key }.map { days, recalls in
                let count = Double(recalls.count)
                let recall = Double(recalls.count { $0 }) / count
                // Laplace smoothing towards the average recall
                return (days: Double(days), recall: (recall * count + averageRecall) / (count + 1), count: count)
            }
            counts[grade] = byDays.values.reduce(0) { $0 + $1.count }
            stabilities[grade] = search(points, defaultStability: FSRSParameters.default[grade.rawValue - 1])
        }
        return smoothAndFill(stabilities, counts: counts).map { Result(stabilities: $0, counts: counts) }
    }

    /// Ternary search for the stability with the least count-weighted log loss, plus a
    /// small penalty for straying from the default.
    private static func search(_ points: [(days: Double, recall: Double, count: Double)], defaultStability: Double) -> Double {
        let decay = -FSRSParameters.default[20]
        let factor = pow(0.9, 1 / decay) - 1
        func loss(_ s: Double) -> Double {
            var total = 0.0
            for point in points {
                let predicted = pow(point.days / s * factor + 1, decay)
                total += -(point.recall * log(predicted) + (1 - point.recall) * log(1 - predicted)) * point.count
            }
            return total + abs(s - defaultStability) / 16
        }

        var low = FSRS.minimumStability
        var high = maximum
        var optimal = defaultStability
        var iterations = 0
        while high - low > Double.ulpOfOne && iterations < 1000 {
            iterations += 1
            let mid1 = low + (high - low) / 3
            let mid2 = high - (high - low) / 3
            if loss(mid1) < loss(mid2) {
                high = mid2
            } else {
                low = mid1
            }
            optimal = (high + low) / 2
        }
        return optimal
    }

    /// Makes the stabilities grow with the grade and fills in grades without data.
    ///
    /// Of two stabilities in the wrong order, the one with more data wins. Missing grades
    /// are extrapolated geometrically with the ratios of fsrs-rs.
    static func smoothAndFill(_ stabilities: [Grade: Double], counts: [Grade: Int]) -> [Double]? {
        var stabilities = stabilities.filter { counts[$0.key] != nil }
        let pairs: [(Grade, Grade)] = [(.again, .hard), (.hard, .good), (.good, .easy), (.again, .good), (.hard, .easy), (.again, .easy)]
        for (small, big) in pairs {
            if let smallValue = stabilities[small], let bigValue = stabilities[big], smallValue > bigValue {
                if counts[small]! > counts[big]! {
                    stabilities[big] = smallValue
                } else {
                    stabilities[small] = bigValue
                }
            }
        }

        let w1 = 0.41
        let w2 = 0.54
        var s = Grade.allCases.map { stabilities[$0] }
        switch stabilities.count {
        case 0:
            return nil
        case 1:
            let (grade, value) = stabilities.first!
            let factor = value / FSRSParameters.default[grade.rawValue - 1]
            s = (0..<4).map { FSRSParameters.default[$0] * factor }.sorted()
        case 2:
            switch (s[0], s[1], s[2], s[3]) {
            case (nil, nil, let r3?, let r4?):
                let r2 = pow(r3, 1 / (1 - w2)) * pow(r4, 1 - 1 / (1 - w2))
                s[1] = r2
                s[0] = pow(r2, 1 / w1) * pow(r3, 1 - 1 / w1)
            case (nil, let r2?, nil, let r4?):
                let r3 = pow(r2, 1 - w2) * pow(r4, w2)
                s[2] = r3
                s[0] = pow(r2, 1 / w1) * pow(r3, 1 - 1 / w1)
            case (nil, let r2?, let r3?, nil):
                s[3] = pow(r2, 1 - 1 / w2) * pow(r3, 1 / w2)
                s[0] = pow(r2, 1 / w1) * pow(r3, 1 - 1 / w1)
            case (let r1?, nil, nil, let r4?):
                let k = w1 / (w1 + w2 - w1 * w2)
                let l = w2 / (w1 + w2 - w1 * w2)
                s[1] = pow(r1, k) * pow(r4, 1 - k)
                s[2] = pow(r1, 1 - l) * pow(r4, l)
            case (let r1?, nil, let r3?, nil):
                let r2 = pow(r1, w1) * pow(r3, 1 - w1)
                s[1] = r2
                s[3] = pow(r2, 1 - 1 / w2) * pow(r3, 1 / w2)
            case (let r1?, let r2?, nil, nil):
                let r3 = pow(r1, 1 - 1 / (1 - w1)) * pow(r2, 1 / (1 - w1))
                s[2] = r3
                s[3] = pow(r2, 1 - 1 / w2) * pow(r3, 1 / w2)
            default:
                break
            }
        case 3:
            switch (s[0], s[1], s[2], s[3]) {
            case (nil, let r2?, let r3?, _):
                s[0] = pow(r2, 1 / w1) * pow(r3, 1 - 1 / w1)
            case (let r1?, nil, let r3?, _):
                s[1] = pow(r1, w1) * pow(r3, 1 - w1)
            case (_, let r2?, nil, let r4?):
                s[2] = pow(r2, 1 - w2) * pow(r4, w2)
            case (_, let r2?, let r3?, nil):
                s[3] = pow(r2, 1 - 1 / w2) * pow(r3, 1 / w2)
            default:
                break
            }
        default:
            break
        }
        return s.map { ($0 ?? FSRS.minimumStability).clamped(to: FSRS.minimumStability...maximum) }
    }
}
