import SwiftUI

/// Kid-friendly settings. Intentionally tiny: sound, haptics, color-blind
/// numbering. A production build would add a parental gate and iCloud toggle.
struct SettingsView: View {
    @AppStorage("pbn.sound") private var soundOn = true
    @AppStorage("pbn.haptics") private var hapticsOn = true
    @AppStorage("pbn.colorblindNumbers") private var colorblindNumbers = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Fun stuff") {
                    Toggle("Sound effects", isOn: $soundOn)
                    Toggle("Haptics", isOn: $hapticsOn)
                }
                Section("Accessibility") {
                    Toggle("Big numbers on color chips", isOn: $colorblindNumbers)
                }
                Section {
                    Text("Made for ages 6–10. All processing happens on your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
