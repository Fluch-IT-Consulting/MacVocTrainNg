import Foundation
import Testing

@testable import MacVocTrain

struct PreferencesTests {
    let domain = "PreferencesTests.\(UUID().uuidString)"

    @Test func reopensDecksByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        Preferences.setUpDefaults(defaults, domain: domain)

        #expect(defaults.persistentDomain(forName: domain)?[Preferences.reopenDecksKey] as? Bool == true)
    }

    @Test func keepsTheChosenSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: Preferences.reopenDecksKey)

        Preferences.setUpDefaults(defaults, domain: domain)

        #expect(defaults.bool(forKey: Preferences.reopenDecksKey) == false)
    }
}
