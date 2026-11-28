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
            lastError = "Bot token missing or invalid"
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
            await sendStatusCard(token: token, chatID: chatID)
        case "/fetch":
            guard !arg.isEmpty else {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Usage: /fetch <bundleId|adamId|url|name>")
                return
            }
            enqueue(chatID: chatID, token: token, label: "fetch \(arg)") {
                let app = try await TelegramWorkerJobs.resolveApp(arg)
                let cards = CardSession(token: token, chatID: chatID, app: app)
                await cards.line("Tetherless fetch")
                let url = try await TelegramWorkerJobs.fetch(app: app) { line, percent in
                    await cards.progress(line, percent: percent)
                }
                await cards.finish(percent: 100, line: "upload encrypted IPA")
                try await Self.sendIPA(token: token, chatID: chatID, fileURL: url, caption: "Fetched \(app.trackName) (encrypted)", cards: cards)
            }
        case "/decrypt":
            guard !arg.isEmpty else {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Usage: /decrypt <path or latest download bundleId>")
                return
            }
            enqueue(chatID: chatID, token: token, label: "decrypt \(arg)") {
                let ipa = try await Self.resolveExistingIPA(arg)
                let cards = CardSession(token: token, chatID: chatID, appName: ipa.deletingPathExtension().lastPathComponent, version: "")
                await cards.line("Tetherless decrypt")
                let out = try await TelegramWorkerJobs.decrypt(ipaURL: ipa) { line, percent in
                    await cards.progress(line, percent: percent)
                }
                await cards.finish(percent: 100, line: "decrypt OK")
                try await Self.sendIPA(token: token, chatID: chatID, fileURL: out, caption: "Decrypted \(out.lastPathComponent)", cards: cards)
            }
        case "/fd", "/fetchdecrypt":
            guard !arg.isEmpty else {
                await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Usage: /fd <bundleId|adamId|url|name>")
                return
            }
            enqueue(chatID: chatID, token: token, label: "fetch+decrypt \(arg)") {
                let app = try await TelegramWorkerJobs.resolveApp(arg)
                let cards = CardSession(token: token, chatID: chatID, app: app)
                await cards.progress("Resolved \(app.trackName)", percent: 0)
                await cards.line("Tetherless fetch")
                let ipa = try await TelegramWorkerJobs.fetch(app: app) { line, percent in
                    await cards.progress(line, percent: percent)
                }
                await cards.progress("Tetherless decrypt", percent: 70)
                let out = try await TelegramWorkerJobs.decrypt(ipaURL: ipa) { line, percent in
                    await cards.progress(line, percent: percent)
                }
                await cards.finish(percent: 99, line: "uploading to Telegram")
                try await Self.sendIPA(token: token, chatID: chatID, fileURL: out, caption: "Ready \(out.lastPathComponent)", cards: cards)
            }
        default:
            await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: "Unknown command. /help")
        }
    }

    private func sendStatusCard(token: String, chatID: Int64) async {
        let account = AppStore.this.selectedAccount?.email ?? "(no App Store account)"
        let busy = jobTask != nil
        if let jpeg = TelegramSharpCard.renderStatus(
            running: isRunning,
            busy: busy,
            account: account,
            lastStatus: lastStatus,
            lastError: lastError
        ) {
            await TelegramBotClient.sendPhoto(token: token, chatID: chatID, jpeg: jpeg, caption: statusText())
        } else {
            await TelegramBotClient.sendMessage(token: token, chatID: chatID, text: statusText())
        }
    }

    private static func sendIPA(
        token: String,
        chatID: Int64,
        fileURL: URL,
        caption: String,
        cards: CardSession
    ) async throws {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let overTelegramCap = size > TelegramBotClient.maxDocumentBytes

        if !overTelegramCap {
            do {
                try await TelegramBotClient.sendDocument(
                    token: token,
                    chatID: chatID,
                    fileURL: fileURL,
                    caption: caption
                )
                await cards.finish(percent: 100, line: "sent to Telegram")
                return
            } catch let error as TelegramBotError {
                if case .fileTooLarge = error {
                    // Fall through to VPS relay.
                } else {
                    throw error
                }
            }
        }

        if TelegramIPARelay.isConfigured {
            await cards.progress("Uploading to VPS (channel delivery)…", percent: 99)
            final class ProgressGate: @unchecked Sendable {
                var last = -1
            }
            let gate = ProgressGate()
            let uploaded = try await TelegramIPARelay.upload(
                fileURL: fileURL,
                chatID: chatID,
                caption: caption
            ) { fraction in
                let pct = Int((fraction * 100).rounded())
                guard pct != gate.last else { return }
                gate.last = pct
                Task { await cards.progress("Relay upload \(pct)%", percent: 99) }
            }
            let mb = Double(uploaded.size) / 1_048_576

            if uploaded.delivered {
                await cards.finish(percent: 100, line: "forwarded from channel")
                // The IPA itself arrives as a bot forward from the drop channel.
                await TelegramBotClient.sendMessage(
                    token: token,
                    chatID: chatID,
                    text: """
                    ✅ \(caption)
                    \(String(format: "%.1f MB", mb)) — posted via Premium → channel, then forwarded here.
                    """.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                return
            }

            if let link = uploaded.url {
                let expires: String
                if let seconds = uploaded.expiresIn {
                    let hours = max(1, seconds / 3600)
                    expires = "Expires in ~\(hours)h."
                } else {
                    expires = ""
                }
                let note = uploaded.deliverError.map { "Channel delivery failed: \($0)\n" } ?? ""
                await cards.finish(percent: 100, line: "relay link sent")
                await TelegramBotClient.sendMessage(
                    token: token,
                    chatID: chatID,
                    text: """
                    ✅ \(caption)
                    \(String(format: "%.1f MB", mb)) — over Bot API ~50 MB.
                    \(note)
                    \(link.absoluteString)

                    \(expires)
                    """.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                return
            }

            throw TelegramIPARelayError.deliveryFailed(
                uploaded.deliverError ?? "VPS relay did not deliver the IPA"
            )
        }

        await cards.fail(line: "error — IPA over ~50 MB (no VPS relay)")
        await TelegramBotClient.sendMessage(
            token: token,
            chatID: chatID,
            text: """
            ❌ IPA is \(String(format: "%.1f", Double(size) / 1_048_576)) MB — Bot API caps ~50 MB.

            Kept on this iPhone:
            `\(fileURL.path)`

            Set IPA relay URL + token in Settings, and on the VPS configure Premium channel delivery
            (TELEGRAM_SESSION + TELEGRAM_CHANNEL_ID + TELEGRAM_BOT_TOKEN). See Tools/telegram-ipa-relay.
            """
        )
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
        let relay = TelegramIPARelay.isConfigured
            ? "configured (channel forward for >~50 MB)"
            : "off (IPAs >~50 MB stay on-device)"
        return """
        Worker: \(isRunning ? "running" : "stopped") (\(busy))
        Account: \(account)
        Decrypt: \(FairPlayDecryptor.isAvailable ? "ready" : "unavailable")
        IPA relay: \(relay)
        Last: \(lastStatus)
        \(lastError.map { "Error: \($0)" } ?? "")
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var helpText: String {
        """
        UNlicense phone worker ready.

        /fd <bundleId|adamId|url|name> — fetch + decrypt, send IPA
        /fetch <target> — download only (encrypted)
        /decrypt <bundleId|filename> — decrypt an on-device IPA
        /status — sharp status card
        /help — this text

        Keep the app open. IPAs over ~50 MB go phone → VPS → Premium account posts to your channel → bot forwards to you (up to ~4 GB).
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

// MARK: - Sharp card session

@MainActor
final class CardSession {
    private let token: String
    private let chatID: Int64
    private var appName: String
    private var version: String
    private var icon: UIImage?
    private var lines: [String] = []
    private var percent: Int = 0
    private var lastSentAt: Date = .distantPast
    private var lastSentPercent: Int = -1
    /// Single Telegram message that we keep editing in place.
    private var messageID: Int?

    init(token: String, chatID: Int64, app: iTunesSearchResult) {
        self.token = token
        self.chatID = chatID
        self.appName = app.trackName
        self.version = app.version
        Task { await self.loadIcon(app.artworkUrl512 ?? app.artworkUrl100) }
    }

    init(token: String, chatID: Int64, appName: String, version: String, icon: UIImage? = nil) {
        self.token = token
        self.chatID = chatID
        self.appName = appName
        self.version = version
        self.icon = icon
    }

    func line(_ text: String) async {
        lines.append(text)
        await push(force: true)
    }

    func progress(_ text: String, percent explicit: Int? = nil) async {
        if let explicit {
            self.percent = max(0, min(100, explicit))
        } else if let match = text.range(of: #"(\d+)\s*%"#, options: .regularExpression) {
            let digits = text[match].filter(\.isNumber)
            if let value = Int(digits) {
                self.percent = max(self.percent, min(100, value))
            }
        }
        // Keep console readable: replace last % line of the same phase when possible.
        if text.contains("%"), let last = lines.last, last.contains("%") {
            lines[lines.count - 1] = text
        } else {
            lines.append(text)
        }
        await push(force: false)
    }

    func finish(percent: Int, line: String) async {
        self.percent = max(0, min(100, percent))
        lines.append(line)
        await push(force: true)
    }

    func fail(line: String) async {
        lines.append(line)
        percent = min(percent, 99)
        await push(force: true, failed: true)
    }

    private func push(force: Bool, failed: Bool = false) async {
        let now = Date()
        let delta = abs(percent - lastSentPercent)
        // One dynamic message: throttle edits so Telegram rate limits stay happy.
        let shouldSend = force
            || failed
            || delta >= 3
            || (delta >= 1 && now.timeIntervalSince(lastSentAt) > 2.5)
            || (percent != lastSentPercent && now.timeIntervalSince(lastSentAt) > 4.0)
        guard shouldSend else { return }
        lastSentAt = now
        lastSentPercent = percent

        let caption = "\(percent)% · \(lines.last ?? appName)"
        let model = TelegramSharpCard.ProgressModel(
            appName: appName,
            version: version,
            icon: icon,
            percent: percent,
            lines: lines,
            failed: failed
        )
        guard let jpeg = TelegramSharpCard.renderProgress(model) else {
            await TelegramBotClient.sendMessage(
                token: token,
                chatID: chatID,
                text: "\(percent)% — \(lines.last ?? appName)"
            )
            return
        }

        if let messageID {
            let edited = await TelegramBotClient.editMessageMedia(
                token: token,
                chatID: chatID,
                messageID: messageID,
                jpeg: jpeg,
                caption: caption
            )
            if edited { return }
            // Edit failed (deleted / rate limit) — fall through and send a fresh card.
            self.messageID = nil
        }

        if let id = await TelegramBotClient.sendPhoto(
            token: token,
            chatID: chatID,
            jpeg: jpeg,
            caption: caption
        ) {
            messageID = id
        }
    }

    private func loadIcon(_ urlString: String?) async {
        guard let urlString, let url = URL(string: urlString) else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let image = UIImage(data: data) {
            icon = image
        }
    }
}
