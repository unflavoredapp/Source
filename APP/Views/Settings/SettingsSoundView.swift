import SwiftUI

struct SettingsSoundView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage(SoundEffects.enabledKey) private var soundEffects = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $soundEffects) {
                    Label("sound_effects".localized, systemImage: "speaker.wave.2.fill")
                }
                .toggleStyle(SoundingToggleStyle())
            } footer: {
                Text("sound_effects".localized)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings_sound".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
