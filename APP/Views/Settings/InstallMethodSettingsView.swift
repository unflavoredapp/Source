import SwiftUI
import UniformTypeIdentifiers

struct InstallMethodSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var method = InstallMethod.current
    @State private var pairingPresent = DevicePairingStore.hasSavedPairing
    @State private var legacyPairingPresent = FileManager.default.fileExists(
        atPath: DeviceInstallationManager.legacyPairingPath
    )
    @StateObject private var manager = DeviceInstallationManager.shared
    @State private var resetError: String?
    @State private var importNotice: String?
    @State private var showPairingImporter = false

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

                        Picker("install_native_mode".localized, selection: $manager.mode) {
                            Text("install_native_mode_builtin".localized).tag(DeviceConnectionMode.builtIn)
                            Text("install_native_mode_manual".localized).tag(DeviceConnectionMode.manual)
                        }
                        .pickerStyle(.segmented)

                        LabeledContent(
                            "install_native_pairing".localized,
                            value: pairingPresent || legacyPairingPresent
                                ? "install_native_pairing_imported".localized
                                : "install_native_pairing_missing".localized
                        )
                        .font(.subheadline)

                        Button("install_native_pairing_import".localized) {
                            showPairingImporter = true
                        }

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

                        if let importNotice {
                            Text(importNotice)
                                .font(.caption)
                                .foregroundStyle(themeManager.accentColor)
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
            legacyPairingPresent = FileManager.default.fileExists(
                atPath: DeviceInstallationManager.legacyPairingPath
            )
        }
        .fileImporter(
            isPresented: $showPairingImporter,
            allowedContentTypes: [.propertyList, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try importLegacyPairing(from: url)
                    legacyPairingPresent = true
                    importNotice = "install_native_pairing_import_ok".localized
                    resetError = nil
                } catch {
                    resetError = error.localizedDescription
                    importNotice = nil
                }
            case .failure(let error):
                resetError = error.localizedDescription
            }
        }
    }

    /// Copies a SideStore / idevice pairing plist into Documents for Manual Setup.
    private func importLegacyPairing(from url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        _ = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dest = URL(fileURLWithPath: DeviceInstallationManager.legacyPairingPath)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: dest, options: .atomic)
    }
}
