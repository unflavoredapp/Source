import SwiftUI

struct SettingsIslandView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var islandSettings = IslandSettings.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $islandSettings.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("live_island".localized)
                        Text("live_island_desc".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SoundingToggleStyle())
            }

            Section {
                Toggle(isOn: $islandSettings.showsDownload) {
                    Label("live_island_download".localized, systemImage: "arrow.down.to.line")
                }
                .toggleStyle(SoundingToggleStyle())

                Toggle(isOn: $islandSettings.showsSign) {
                    Label("live_island_sign".localized, systemImage: "signature")
                }
                .toggleStyle(SoundingToggleStyle())

                Toggle(isOn: $islandSettings.showsDecrypt) {
                    Label("live_island_decrypt".localized, systemImage: "lock.open")
                }
                .toggleStyle(SoundingToggleStyle())

                Toggle(isOn: $islandSettings.showsInstall) {
                    Label("live_island_install".localized, systemImage: "shippingbox")
                }
                .toggleStyle(SoundingToggleStyle())
            }
            .disabled(!islandSettings.isEnabled)
            .opacity(islandSettings.isEnabled ? 1 : 0.45)
        }
        .navigationTitle("settings_island".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
