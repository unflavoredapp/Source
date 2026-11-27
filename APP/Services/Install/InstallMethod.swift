import Foundation

/// How signed IPAs are delivered to this device after signing.
/// OTA uses itms-services over the local HTTPS installer (existing path).
/// Native uses the built-in packet-tunnel VPN + idevice pairing stack
/// ported from AppAssassin / Random (`NATIVE_INSTALL.md`).
enum InstallMethod: String, CaseIterable, Identifiable {
    case ota
    case native

    static let storageKey = "APP.installMethod"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ota: return "install_method_ota".localized
        case .native: return "install_method_native".localized
        }
    }

    var subtitle: String {
        switch self {
        case .ota: return "install_method_ota_hint".localized
        case .native: return "install_method_native_hint".localized
        }
    }

    static var current: InstallMethod {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? InstallMethod.ota.rawValue
        return InstallMethod(rawValue: raw) ?? .ota
    }

    static func setCurrent(_ method: InstallMethod) {
        UserDefaults.standard.set(method.rawValue, forKey: storageKey)
    }
}
