import SwiftUI

/// App-wide preferences (⌘,).
struct SettingsView: View {
    @AppStorage(Preferences.autoAdvanceKey) private var autoAdvance = true

    var body: some View {
        Form {
            Section {
                Toggle("Continue automatically after a correct answer", isOn: $autoAdvance)
            } footer: {
                Text("When off, you rate every answer yourself, e.g. as Easy.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
