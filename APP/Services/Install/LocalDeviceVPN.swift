import Foundation
import NetworkExtension

/// Starts the embedded packet-tunnel appex that reflects the local 10.7.0.0/24
/// loop used by idevice. The appex is identified by `APPLocalDeviceTunnel` in
/// its Info.plist (see `APPDeviceTunnel/`).
@MainActor
final class LocalDeviceVPN {
    private var manager: NETunnelProviderManager?
    private var startedByAPP = false
    private var restorationNeeded = false
    private let extensionIdentifier: @MainActor () -> String?

    init(extensionIdentifier: @escaping @MainActor () -> String? = { LocalDeviceVPN.extensionBundleIdentifier }) {
        self.extensionIdentifier = extensionIdentifier
    }

    static var extensionBundleIdentifier: String? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        else { return nil }
        return urls.compactMap { Bundle(url: $0) }.first {
            $0.object(forInfoDictionaryKey: "APPLocalDeviceTunnel") as? Bool == true
        }?.bundleIdentifier
    }

    var isConnected: Bool { manager?.connection.status == .connected }

    var isExtensionEmbedded: Bool { extensionIdentifier() != nil }

    func connect(restarting: Bool = false) async throws {
        try Task.checkCancellation()
        guard let extensionID = extensionIdentifier() else {
            throw DeviceSetupError("install_native_missing_tunnel".localized)
        }
        let configurations: [NETunnelProviderManager] = try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: managers ?? []) }
            }
        }
        try Task.checkCancellation()
        let manager = configurations.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionID
        } ?? NETunnelProviderManager()
        self.manager = manager
        let existing = manager.protocolConfiguration as? NETunnelProviderProtocol
        let needsConfiguration = existing?.providerBundleIdentifier != extensionID
            || existing?.serverAddress != "On this device"
            || existing?.disconnectOnSleep != false
            || !manager.isEnabled
            || manager.isOnDemandEnabled
        if restarting || needsConfiguration {
            manager.connection.stopVPNTunnel()
            let deadline = Date().addingTimeInterval(20)
            while manager.connection.status != .disconnected && manager.connection.status != .invalid {
                try Task.checkCancellation()
                guard Date() < deadline else {
                    throw DeviceSetupError("install_native_vpn_stuck".localized)
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            try Task.checkCancellation()
            let config = NETunnelProviderProtocol()
            config.providerBundleIdentifier = extensionID
            config.serverAddress = "On this device"
            config.disconnectOnSleep = false
            manager.protocolConfiguration = config
            manager.localizedDescription = "APP Local Installation"
            manager.isEnabled = true
            manager.isOnDemandEnabled = false
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                manager.saveToPreferences { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                manager.loadFromPreferences { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
        if manager.connection.status == .connected { return }
        try Task.checkCancellation()
        let deadline = Date().addingTimeInterval(20)
        while manager.connection.status == .disconnecting {
            try Task.checkCancellation()
            guard Date() < deadline else {
                throw DeviceSetupError("install_native_vpn_disconnecting".localized)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if manager.connection.status != .connecting && manager.connection.status != .reasserting {
            try manager.connection.startVPNTunnel()
            startedByAPP = true
            restorationNeeded = true
        }
        while manager.connection.status != .connected {
            try Task.checkCancellation()
            guard Date() < deadline else {
                throw DeviceSetupError("install_native_vpn_connect_failed".localized)
            }
            if manager.connection.status == .invalid {
                throw DeviceSetupError("install_native_vpn_invalid".localized)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    func disconnectIfOwned() {
        guard startedByAPP, let manager else { return }
        manager.connection.stopVPNTunnel()
        startedByAPP = false
        _ = restorationNeeded
    }
}
