import SwiftUI

/// App-wide preferences (⌘,).
struct PreferencesView: View {
    @AppStorage(Preferences.autoAdvanceKey) private var autoAdvance = true

    var body: some View {
        Form {
            Section {
                Toggle("Continue automatically when the response is correct", isOn: $autoAdvance)
            } footer: {
                Text("When off, you grade every review yourself, e.g. as Easy.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
