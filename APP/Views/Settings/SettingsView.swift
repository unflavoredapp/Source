import SwiftUI
import UIKit
import Foundation

struct SettingsView: View {
    @State private var currentIcon = AppIconManager.shared.currentAlternateIconName
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var tabBarStyleManager: TabBarStyleManager

    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var showAccountSheet = false
    @State private var showUpdateSheet = false
    @State private var showingIconSuccess = false
    @State private var showingIconError = false
    @State private var iconErrorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackdrop()
                    .environmentObject(themeManager)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        accountHeaderSection

                        VStack(spacing: 0) {
                            settingsLink(
                                title: "settings_appearance_color".localized,
                                systemImage: "paintpalette.fill",
                                destination: AppearanceView()
                                    .environmentObject(themeManager)
                            )
                            divider
                            settingsLink(
                                title: "language".localized,
                                systemImage: "globe",
                                destination: LanguageSettingsView()
                                    .environmentObject(themeManager),
                                trailing: LanguageManager.shared.currentLanguage.nativeName
                            )
                            divider
                            settingsLink(
                                title: "settings_tab_bar".localized,
                                systemImage: "rectangle.bottomthird.inset.filled",
                                destination: SettingsTabBarView()
                                    .environmentObject(themeManager)
                                    .environmentObject(tabBarStyleManager)
                            )
                            divider
                            settingsLink(
                                title: "settings_sound".localized,
                                systemImage: "speaker.wave.2.fill",
                                destination: SettingsSoundView()
                                    .environmentObject(themeManager)
                            )
                            divider
                            settingsLink(
                                title: "settings_island".localized,
                                systemImage: "dot.radiowaves.left.and.right",
                                destination: SettingsIslandView()
                                    .environmentObject(themeManager)
                            )
                            divider
                            settingsLink(
                                title: "settings_app_icon".localized,
                                systemImage: "app.fill",
                                destination: AppIconView(currentIcon: $currentIcon)
                                    .environmentObject(themeManager)
                            )
                        }
                        .liquidGlassSurface(cornerRadius: 16)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)

                        VStack(spacing: 0) {
                            installMethodRow
                            divider
                            telegramWorkerRow
                            divider
                            updateRow
                        }
                        .liquidGlassSurface(cornerRadius: 16)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)

                        versionFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    // Clear the floating tab bar so the version footer isn't clipped.
                    .padding(.bottom, 120)
                }
                .background(Color.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("tab_settings".localized)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                currentIcon = AppIconManager.shared.currentAlternateIconName
            }
            .fullScreenCover(isPresented: $showAccountSheet) {
                AccountSheetView()
                    .environmentObject(appStore)
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $showUpdateSheet) {
                UpdateSheet(checker: updateChecker)
                    .environmentObject(themeManager)
            }
            .alert("icon_set_success".localized, isPresented: $showingIconSuccess) {
                Button("ok".localized, role: .cancel) { }
            }
            .alert("icon_set_failed".localized, isPresented: $showingIconError) {
                Button("ok".localized, role: .cancel) { }
            } message: {
                Text(iconErrorMessage)
            }
        }
    }

    private var divider: some View {
        Divider().padding(.leading, 56)
    }

    private func settingsLink<Destination: View>(
        title: String,
        systemImage: String,
        destination: Destination,
        trailing: String? = nil
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(themeManager.accentColor))

                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle(), sound: .tick)
    }

    private var accountHeaderSection: some View {
        Button(action: {
            showAccountSheet = true
        }) {
            if let account = appStore.selectedAccount {
                HStack(spacing: 16) {
                    ZStack {
                        AccountAvatarButton(size: 64)

                        Circle()
                            .stroke(themeManager.accentColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 72, height: 72)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.fullName.isEmpty ? account.email : account.fullName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if !account.fullName.isEmpty {
                            Text(account.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            Text(flag(country: account.countryCode))
                                .font(.caption)
                            Text(countryName(account.countryCode))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: 16) {
                    Text("👤")
                        .font(.system(size: 64))
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("sign_in_apple_id".localized)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("sign_in_apple_id_desc".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .liquidGlassSurface(cornerRadius: 16)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private func flag(country: String) -> String {
        let base: UInt32 = 127397
        var s = ""
        for v in country.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + v.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s
    }

    private func countryName(_ code: String) -> String {
        LanguageManager.shared.locale.localizedString(forRegionCode: code) ?? code.uppercased()
    }

    private var versionFooter: some View {
        VStack(spacing: 3) {
            Text("UNlicense")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(UpdateChecker.shared.currentVersion)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var installMethodRow: some View {
        NavigationLink(
            destination: InstallMethodSettingsView()
                .environmentObject(themeManager)
        ) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(themeManager.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text("install_method_title".localized)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    Text(InstallMethod.current.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var telegramWorkerRow: some View {
        NavigationLink(
            destination: TelegramWorkerSettingsView()
                .environmentObject(themeManager)
        ) {
            HStack(spacing: 12) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(themeManager.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text("telegram_worker_title".localized)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    Text(
                        TelegramWorkerConfig.isEnabled
                            ? "telegram_worker_running".localized
                            : "telegram_worker_stopped".localized
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var updateRow: some View {
        Button {
            switch updateChecker.state {
            case .available:
                showUpdateSheet = true
            default:
                Task {
                    await updateChecker.check()
                    if case .available = updateChecker.state {
                        showUpdateSheet = true
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(themeManager.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text("check_updates".localized)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    Text("unlicense.cc/updates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                updateStatusView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain, sound: .tap)
        .disabled(updateChecker.state == .checking)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.state {
        case .idle:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        case .checking:
            ProgressView()
                .scaleEffect(0.75)
        case .upToDate:
            Text("update_latest".localized)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .available(let version, _):
            HStack(spacing: 4) {
                Text("v\(version)")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(themeManager.accentColor)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .trailing)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(ThemeManager.shared)
            .environmentObject(AppStore.this)
            .environmentObject(TabBarStyleManager.shared)
    }
}
