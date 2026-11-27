import Foundation
import Security

/// Settings for the on-device Telegram phone worker.
/// The iPhone polls the bot and runs fetch/decrypt jobs locally (FairPlay needs the device).
enum TelegramWorkerConfig {
    private static let enabledKey = "TelegramWorker.enabled"
    private static let chatIDsKey = "TelegramWorker.allowedChatIDs"
    private static let offsetKey = "TelegramWorker.updateOffset"
    private static let tokenService = "TelegramWorker.botToken"

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
            if newValue.isEmpty {
                Keychain.delete(service: tokenService)
            } else {
                Keychain.write(service: tokenService, value: newValue)
            }
            NotificationCenter.default.post(name: .telegramWorkerConfigChanged, object: nil)
        }
    }

    static var isConfigured: Bool {
        !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
