import Foundation
import UIKit

/// On-device worker: keep APP open (or backgrounded briefly), poll Telegram, run fetch/decrypt.
@MainActor
final class TelegramWorker: ObservableObject {
    static let shared = TelegramWorker()

    @Published private(set) var isRunning = false
    @Published private(set) var lastStatus = "Idle"
    @Published private(set) var lastError: String?

    private var loopTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    private var lockedChatID: Int64?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        NotificationCenter.default.addObserver(
            forName: .telegramWorkerConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
    }

    func reconcile() {
        if TelegramWorkerConfig.isEnabled && TelegramWorkerConfig.isConfigured {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard TelegramWorkerConfig.isConfigured else {
            lastError = "Bot token missing"
            lastStatus = "Not configured"
            return
        }
        guard loopTask == nil else { return }
        isRunning = true
        lastError = nil
        lastStatus = "Polling…"
        loopTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        jobTask?.cancel()
        jobTask = nil
        isRunning = false
        lastStatus = "Stopped"
        endBackgroundTask()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            guard TelegramWorkerConfig.isEnabled, TelegramWorkerConfig.isConfigured else { break }
            let token = TelegramWorkerConfig.botToken
            beginBackgroundTask()
            do {
                let updates = try await TelegramBotClient.getUpdates(
                    token: token,
                    offset: TelegramWorkerConfig.updateOffset,
                    timeout: 25
                )
                for update in updates {
                    TelegramWorkerConfig.updateOffset = update.update_id + 1
                    if let message = update.message {
                        await handle(message: message, token: token)
                    }
                }
                lastStatus = "Polling…"
                lastError = nil
            } catch {
                if Task.isCancelled { break }
                lastError = error.localizedDescription
                lastStatus = "Retrying…"
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            endBackgroundTask()
        }
        isRunning = false
        lastStatus = "Stopped"
    }

    private func handle(message: TelegramMessage, token: String) async {
        let chatID = message.chat.id
        guard isAuthorized(chatID: chatID) else {
            await TelegramBotClient.sendMessage(
                token: token,
                chatID: chatID,
                text: "Unauthorized chat. Add this chat id in Settings › Telegram Worker: \(chatID)"
            )
            return
        }

        let text = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/") else { return }

        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let command = parts.first.map(String.init)?.lowercased() ?? ""
        let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch command {
        case "/start", "/help":
            await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: Self.helpText)
        case "/status":
            await TelegramBotClient.sendMessage(
                token: token,
                chatID: chatID,
                text: statusText()
            )
        case "/fetch":
            guard !arg.isEmpty else {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Usage: /fetch <bundleId|adamId|url|name>")
                return
            }
            enqueue(chatID: chatID, token: token, label: "fetch \(arg)") {
                let app = try await TelegramWorkerJobs.resolveApp(arg)
                let url = try await TelegramWorkerJobs.fetch(app: app) { line in
                    await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: line)
                }
                try await TelegramBotClient.sendDocument(
                    token: token,
                    chatID: chatID,
                    fileURL: url,
                    caption: "Fetched \(app.trackName) (encrypted)"
                )
            }
        case "/decrypt":
            guard !arg.isEmpty else {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Usage: /decrypt <path or latest download bundleId>")
                return
            }
            enqueue(chatID: chatID, token: token, label: "decrypt \(arg)") {
                let ipa = try await Self.resolveExistingIPA(arg)
                let out = try await TelegramWorkerJobs.decrypt(ipaURL: ipa) { line in
                    await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: line)
                }
                try await TelegramBotClient.sendDocument(
                    token: token,
                    chatID: chatID,
                    fileURL: out,
                    caption: "Decrypted \(out.lastPathComponent)"
                )
            }
        case "/fd", "/fetchdecrypt":
            guard !arg.isEmpty else {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Usage: /fd <bundleId|adamId|url|name>")
                return
            }
            enqueue(chatID: chatID, token: token, label: "fetch+decrypt \(arg)") {
                let out = try await TelegramWorkerJobs.fetchAndDecrypt(arg) { line in
                    await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: line)
                }
                try await TelegramBotClient.sendDocument(
                    token: token,
                    chatID: chatID,
                    fileURL: out,
                    caption: "Ready \(out.lastPathComponent)"
                )
            }
        default:
            await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Unknown command. /help")
        }
    }

    private func enqueue(chatID: Int64, token: String, label: String, work: @escaping @MainActor () async throws -> Void) {
        if jobTask != nil {
            Task {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Busy with another job. Try /status.")
            }
            return
        }
        lastStatus = "Running: \(label)"
        jobTask = Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.jobTask = nil
                    self?.lastStatus = "Polling…"
                }
            }
            do {
                try await work()
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Done: \(label)")
            } catch is CancellationError {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Cancelled: \(label)")
            } catch {
                await MainActor.run { self?.lastError = error.localizedDescription }
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Error: \(error.localizedDescription)")
            }
        }
    }

    private func isAuthorized(chatID: Int64) -> Bool {
        let allowed = TelegramWorkerConfig.allowedChatIDs
        if !allowed.isEmpty {
            return allowed.contains(chatID)
        }
        if let lockedChatID {
            return lockedChatID == chatID
        }
        lockedChatID = chatID
        TelegramWorkerConfig.allowedChatIDsRaw = String(chatID)
        return true
    }

    private func statusText() -> String {
        let account = AppStore.this.selectedAccount?.email ?? "(no App Store account)"
        let busy = jobTask == nil ? "idle" : "busy"
        return """
        Worker: \(isRunning ? "running" : "stopped") (\(busy))
        Account: \(account)
        Decrypt entitlement probe: \(FairPlayDecryptor.isAvailable ? "work dir ok" : "no work dir")
        Last: \(lastStatus)
        \(lastError.map { "Error: \($0)" } ?? "")
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var helpText: String {
        """
        Phone worker ready.

        /fd <bundleId|adamId|url|name> — fetch + decrypt, send IPA
        /fetch <target> — download only (encrypted)
        /decrypt <bundleId|filename> — decrypt an on-device IPA
        /status — worker + account state
        /help — this text

        Keep the app open (or recently used). Sign in to App Store in APP first.
        """
    }

    private static func resolveExistingIPA(_ arg: String) async throws -> URL {
        if arg.hasPrefix("/"), FileManager.default.fileExists(atPath: arg) {
            return URL(fileURLWithPath: arg)
        }
        if let match = UnifiedDownloadManager.shared.downloadRequests.first(where: {
            $0.runtime.status == .completed
                && ($0.bundleIdentifier.caseInsensitiveCompare(arg) == .orderedSame
                    || $0.name.localizedCaseInsensitiveContains(arg)
                    || ($0.localFilePath?.contains(arg) ?? false))
        }), let path = match.localFilePath {
            return URL(fileURLWithPath: path)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloads = docs.appendingPathComponent("Downloads", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil),
           let hit = files.first(where: { $0.lastPathComponent.localizedCaseInsensitiveContains(arg) && $0.pathExtension.lowercased() == "ipa" }) {
            return hit
        }
        throw TelegramWorkerJobs.JobError.notFound(arg)
    }

    private func beginBackgroundTask() {
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "telegram-worker") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
