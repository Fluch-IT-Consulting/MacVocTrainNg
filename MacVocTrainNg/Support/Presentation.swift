import SwiftUI
import VocabCore

// User-facing names and colours for values of the core model.

extension MaturityCategory {
    var title: String {
        switch self {
        case .new: String(localized: "New")
        case .shaky: String(localized: "Shaky")
        case .young: String(localized: "Young")
        case .maturing: String(localized: "Maturing")
        case .mature: String(localized: "Mature")
        case .mastered: String(localized: "Mastered")
        }
    }

    var explanation: String {
        switch self {
        case .new: String(localized: "Never studied")
        case .shaky: String(localized: "Remembered for less than 4 days")
        case .young: String(localized: "Remembered for 4 to 16 days")
        case .maturing: String(localized: "Remembered for 16 to 64 days")
        case .mature: String(localized: "Remembered for 64 to 256 days")
        case .mastered: String(localized: "Remembered for 256 days or more")
        }
    }

    /// An ordinal one-hue ramp (validated for colour-vision deficiencies in light
    /// and dark mode): the higher the maturity, the more prominent the blue.
    /// New cards are neutral grey, outside the ramp.
    var color: Color {
        switch self {
        case .new: Color(light: 0xB4B2AC, dark: 0x5E5D59)
        case .shaky: Color(light: 0x86B6EF, dark: 0x1C5CAB)
        case .young: Color(light: 0x5598E7, dark: 0x2A78D6)
        case .maturing: Color(light: 0x2A78D6, dark: 0x5598E7)
        case .mature: Color(light: 0x1C5CAB, dark: 0x86B6EF)
        case .mastered: Color(light: 0x104281, dark: 0xB7D3F6)
        }
    }
}

extension Grade {
    var title: String {
        switch self {
        case .again: String(localized: "Again")
        case .hard: String(localized: "Hard")
        case .good: String(localized: "Good")
        case .easy: String(localized: "Easy")
        }
    }

    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character(String(rawValue)))
    }

    /// Status colours; always shown together with the grade's title.
    var color: Color {
        switch self {
        case .again: Color(light: 0xD03B3B, dark: 0xD03B3B)
        case .hard: Color(light: 0xEC835A, dark: 0xEC835A)
        case .good: Color(light: 0x0CA30C, dark: 0x0CA30C)
        case .easy: Color(light: 0x2A78D6, dark: 0x3987E5)
        }
    }
}

extension LearningPhase {
    var title: String {
        switch self {
        case .learning: String(localized: "Learning")
        case .review: String(localized: "Review phase")
        case .relearning: String(localized: "Relearning")
        }
    }
}

enum Format {
    /// A duration in days, e.g. "12 days" or "less than a day".
    static func days(_ days: Double) -> String {
        guard days >= 1 else { return String(localized: "less than a day") }
        let rounded = Int(days.rounded())
        return String(localized: "\(rounded) days")
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// When a card is due, relative to now; `nil` for a card without a learning state.
    static func due(_ due: Date?, now: Date) -> String {
        guard let due else { return String(localized: "New") }
        if due <= now { return String(localized: "Now") }
        return due.formatted(.relative(presentation: .named))
    }
}

extension Color {
    /// A colour that adapts to light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            })
    }
}
