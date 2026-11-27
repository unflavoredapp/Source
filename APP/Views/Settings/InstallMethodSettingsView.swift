import SwiftUI

struct InstallMethodSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var method = InstallMethod.current
    @State private var pairingPresent = DevicePairingStore.hasSavedPairing
    @State private var resetError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("install_method_title".localized)
                    .font(.title2.weight(.bold))

                Text("install_method_intro".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("install_method_title".localized, selection: $method) {
                    ForEach(InstallMethod.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: method) { _, newValue in
                    InstallMethod.setCurrent(newValue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(method.subtitle, systemImage: method == .native ? "iphone.and.arrow.forward" : "globe")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassSurface(cornerRadius: 16)

                if method == .native {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            NativeInstaller.isStackReady
                                ? "install_native_ready".localized
                                : NativeInstaller.readinessMessage,
                            systemImage: NativeInstaller.isStackReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(NativeInstaller.isStackReady ? themeManager.accentColor : .orange)

                        LabeledContent(
                            "install_native_pairing".localized,
                            value: pairingPresent
                                ? "install_native_pairing_imported".localized
                                : "install_native_pairing_missing".localized
                        )
                        .font(.subheadline)

                        if pairingPresent {
                            Button("install_native_pairing_reset".localized, role: .destructive) {
                                do {
                                    try DevicePairingStore.reset()
                                    pairingPresent = false
                                    resetError = nil
                                } catch {
                                    resetError = error.localizedDescription
                                }
                            }
                        }

                        if let resetError {
                            Text(resetError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Text("install_native_requirements".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassSurface(cornerRadius: 16)
                }
            }
            .padding(20)
        }
        .background(LiquidGlassBackdrop().environmentObject(themeManager).ignoresSafeArea())
        .navigationTitle("install_method_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            method = InstallMethod.current
            pairingPresent = DevicePairingStore.hasSavedPairing
        }
    }
}
