import Foundation
import Security

/// Settings for the on-device Telegram phone worker.
/// The iPhone polls the bot and runs fetch/decrypt jobs locally (FairPlay needs the device).
enum TelegramWorkerConfig {
    private static let enabledKey = "TelegramWorker.enabled"
    private static let chatIDsKey = "TelegramWorker.allowedChatIDs"
    private static let offsetKey = "TelegramWorker.updateOffset"
    private static let relayURLKey = "TelegramWorker.relayBaseURL"
    private static let appsCountKey = "TelegramWorker.completedAppsCount"
    private static let tokenService = "TelegramWorker.botToken"
    private static let relayTokenService = "TelegramWorker.relayToken"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: .telegramWorkerConfigChanged, object: nil)
        }
    }

    /// Comma/space-separated chat IDs allowed to issue commands. Empty = first chat that messages wins (then locked).
    static var allowedChatIDsRaw: String {
        get { UserDefaults.standard.string(forKey: chatIDsKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: chatIDsKey)
            NotificationCenter.default.post(name: .telegramWorkerConfigChanged, object: nil)
        }
    }

    static var allowedChatIDs: Set<Int64> {
        let parts = allowedChatIDsRaw
            .split { $0 == "," || $0 == " " || $0 == ";" || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { Int64($0) }
        return Set(parts)
    }

    static var updateOffset: Int {
        get { UserDefaults.standard.integer(forKey: offsetKey) }
        set { UserDefaults.standard.set(newValue, forKey: offsetKey) }
    }

    static var botToken: String {
        get { Keychain.read(service: tokenService) ?? "" }
        set {
            let normalized = TelegramBotClient.normalizedToken(newValue)
            if normalized.isEmpty {
                Keychain.delete(service: tokenService)
            } else {
                Keychain.write(service: tokenService, value: normalized)
            }
            NotificationCenter.default.post(name: .telegramWorkerConfigChanged, object: nil)
        }
    }

    static var isConfigured: Bool {
        TelegramBotClient.validateToken(botToken)
    }

    /// Public HTTPS origin of the VPS IPA relay (no trailing slash), e.g. `https://ipa.example.com`.
    static var relayBaseURL: String {
        get { UserDefaults.standard.string(forKey: relayURLKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: relayURLKey)
            NotificationCenter.default.post(name: .telegramWorkerConfigChanged, object: nil)
        }
    }

    /// Shared secret matching `RELAY_TOKEN` on the VPS.
    static var relayToken: String {
        get { Keychain.read(service: relayTokenService) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Keychain.delete(service: relayTokenService)
            } else {
                Keychain.write(service: relayTokenService, value: trimmed)
            }
            NotificationCenter.default.post(name: .telegramWorkerConfigChanged, object: nil)
        }
    }

    static var isRelayConfigured: Bool {
        let base = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relayToken.isEmpty, let url = URL(string: base), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    /// Successful Telegram Worker deliveries (shown as “N apps” next to DELvEK).
    static var completedAppsCount: Int {
        get { UserDefaults.standard.integer(forKey: appsCountKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: appsCountKey) }
    }

    /// Apps count shown next to DELvEK on sharp cards.
    static var displayedAppsCount: Int {
        completedAppsCount
    }

    static func recordCompletedApp() {
        completedAppsCount += 1
    }

    private enum Keychain {
        static func write(service: String, value: String) {
            let data = Data(value.utf8)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "default",
            ]
            SecItemDelete(query as CFDictionary)
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }

        static func read(service: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "default",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func delete(service: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "default",
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

extension Notification.Name {
    static let telegramWorkerConfigChanged = Notification.Name("TelegramWorkerConfigChanged")
}
