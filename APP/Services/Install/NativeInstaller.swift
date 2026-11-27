import Foundation

/// Facade for native (VPN + idevice) installs.
///
/// Full install currently requires the IDeviceKit package, the `APPDeviceTunnel`
/// Network Extension target, and a profile that allows `packet-tunnel-provider`.
/// Until that Xcode wiring lands, selecting Native surfaces a clear readiness
/// error and signing keeps the existing OTA path as a safe fallback when asked.
@MainActor
enum NativeInstaller {
    static var isSelected: Bool { InstallMethod.current == .native }

    static var isStackReady: Bool {
        #if canImport(IDeviceSwift)
        return LocalDeviceVPN.extensionBundleIdentifier != nil
        #else
        return false
        #endif
    }

    static var readinessMessage: String {
        if isStackReady { return "install_native_ready".localized }
        if LocalDeviceVPN.extensionBundleIdentifier == nil {
            return "install_native_missing_tunnel".localized
        }
        return "install_native_missing_idevice".localized
    }

    enum InstallError: LocalizedError {
        case notReady(String)
        case ipaMissing

        var errorDescription: String? {
            switch self {
            case .notReady(let message): return message
            case .ipaMissing: return "sign_install_ipa_missing".localized
            }
        }
    }

    static func install(
        ipaURL: URL,
        bundleID: String,
        name: String,
        version: String,
        onPhase: (@MainActor (SigningInstallPhase) -> Void)? = nil
    ) async throws {
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw InstallError.ipaMissing
        }
        guard isStackReady else {
            throw InstallError.notReady(readinessMessage)
        }

        #if canImport(IDeviceSwift)
        onPhase?(.connecting)
        // DeviceInstallationManager / IDeviceInstallationWorker land in the
        // follow-up that links IDeviceKit into APP.xcodeproj.
        throw InstallError.notReady("install_native_wiring_pending".localized)
        #else
        throw InstallError.notReady(readinessMessage)
        #endif
    }
}
