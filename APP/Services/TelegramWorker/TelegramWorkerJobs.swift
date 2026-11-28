import Foundation

@MainActor
enum TelegramWorkerJobs {
    enum JobError: LocalizedError {
        case noAccount
        case notFound(String)
        case downloadFailed(String)
        case decryptFailed(String)
        case timeout(String)

        var errorDescription: String? {
            switch self {
            case .noAccount: return "Sign in to an App Store account in the app first."
            case .notFound(let t): return "App not found: \(t)"
            case .downloadFailed(let t): return "Download failed: \(t)"
            case .decryptFailed(let t): return "Decrypt failed: \(t)"
            case .timeout(let t): return "Timed out: \(t)"
            }
        }
    }

    /// Resolve bundle id, numeric adam/track id, or App Store URL → iTunes result.
    static func resolveApp(_ target: String) async throws -> iTunesSearchResult {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = AppStore.this.selectedAccount?.countryCode ?? "us"

        if let trackId = Int(trimmed), trackId > 0 {
            if let hit = try await iTunesClient.shared.lookup(trackId: trackId, countryCode: region) {
                return hit
            }
        }

        if trimmed.contains("apps.apple.com") || trimmed.contains("itunes.apple.com"),
           let id = extractAdamID(from: trimmed),
           let hit = try await iTunesClient.shared.lookup(trackId: id, countryCode: region) {
            return hit
        }

        if trimmed.contains("."),
           let hit = try await iTunesClient.shared.lookup(bundleIdentifier: trimmed, countryCode: region) {
            return hit
        }

        if let results = try await iTunesClient.shared.search(term: trimmed, limit: 5, countryCode: region),
           let first = results.first {
            return first
        }

        throw JobError.notFound(trimmed)
    }

    /// `percent` is overall job progress 0…100 for sharp-card rings (nil = message only).
    typealias ProgressHandler = (_ message: String, _ percent: Int?) async -> Void

    static func fetch(app: iTunesSearchResult, onProgress: @escaping ProgressHandler) async throws -> URL {
        guard AppStore.this.selectedAccount != nil else { throw JobError.noAccount }

        let downloadId = UnifiedDownloadManager.shared.addDownload(
            bundleIdentifier: app.bundleId,
            name: app.trackName,
            version: app.version,
            identifier: app.trackId,
            iconURL: app.artworkUrl512,
            versionId: nil,
            price: app.price,
            currency: app.currency
        )

        guard let request = UnifiedDownloadManager.shared.downloadRequests.first(where: { $0.id == downloadId }) else {
            throw JobError.downloadFailed("could not create download request")
        }

        await onProgress("Downloading \(app.trackName) \(app.version)…", 1)
        UnifiedDownloadManager.shared.startDownload(for: request)

        var lastReported = -1
        let deadline = Date().addingTimeInterval(60 * 45)
        while Date() < deadline {
            try Task.checkCancellation()
            if let live = UnifiedDownloadManager.shared.downloadRequests.first(where: { $0.id == downloadId }) {
                switch live.runtime.status {
                case .completed:
                    await onProgress("Download 100%", 70)
                    if let path = live.localFilePath {
                        return URL(fileURLWithPath: path)
                    }
                    throw JobError.downloadFailed("completed without file path")
                case .failed, .cancelled:
                    throw JobError.downloadFailed(live.runtime.error ?? live.runtime.status.rawValue)
                case .downloading, .waiting, .paused:
                    let raw = max(0, min(100, Int((live.runtime.progressValue * 100).rounded())))
                    // Map download into 1…70 of the overall sharp-card ring.
                    let mapped = max(1, Int((Double(raw) / 100.0 * 70.0).rounded()))
                    if raw != lastReported {
                        lastReported = raw
                        await onProgress("Download \(raw)%", mapped)
                    }
                }
            }
            try await Task.sleep(nanoseconds: 750_000_000)
        }
        throw JobError.timeout("download")
    }

    static func decrypt(ipaURL: URL, onProgress: @escaping ProgressHandler) async throws -> URL {
        let meta = IPAMetadata.read(at: ipaURL)
        DecryptInboxStore.shared.reload()

        func matchingJob() -> DecryptJob? {
            DecryptInboxStore.shared.jobs.first(where: { candidate in
                if let meta {
                    return candidate.metadata.bundleIdentifier == meta.bundleIdentifier
                        && candidate.metadata.version == meta.version
                }
                return candidate.url.standardizedFileURL.path == ipaURL.standardizedFileURL.path
                    || candidate.url.lastPathComponent == ipaURL.lastPathComponent
            })
        }

        if let existing = matchingJob() {
            if existing.state == .completed, let out = existing.outputURL {
                await onProgress("Decrypt already done", 98)
                return out
            }
            await onProgress("Decrypting \(existing.displayName)…", 72)
            DecryptInboxStore.shared.start(existing)
            return try await waitForDecrypt(job: existing, onProgress: onProgress)
        }

        await onProgress("Importing for decrypt…", 71)
        let failures = await DecryptInboxStore.shared.importIPAs(from: [ipaURL])
        if let first = failures.first, !first.lowercased().contains("dup") {
            throw JobError.decryptFailed(first)
        }

        guard let job = matchingJob() ?? DecryptInboxStore.shared.jobs.first else {
            throw JobError.decryptFailed("import produced no job")
        }

        if job.state == .completed, let out = job.outputURL {
            await onProgress("Decrypt already done", 98)
            return out
        }

        await onProgress("Decrypting \(job.displayName)…", 72)
        DecryptInboxStore.shared.start(job)
        return try await waitForDecrypt(job: job, onProgress: onProgress)
    }

    private static func waitForDecrypt(job: DecryptJob, onProgress: @escaping ProgressHandler) async throws -> URL {
        var lastReported = -1
        let deadline = Date().addingTimeInterval(60 * 45)
        while Date() < deadline {
            try Task.checkCancellation()
            let fraction = job.log.fraction
            let raw = max(0, min(100, Int((fraction * 100).rounded())))
            // Map decrypt into 72…98 of the overall ring.
            let mapped = 72 + Int((Double(raw) / 100.0 * 26.0).rounded())
            if raw != lastReported {
                lastReported = raw
                let phase = job.log.phase.isEmpty ? "Decrypt" : job.log.phase
                await onProgress("\(phase) \(raw)%", mapped)
            }
            switch job.state {
            case .completed:
                await onProgress("Decrypt 100%", 98)
                if let out = job.outputURL { return out }
                throw JobError.decryptFailed("completed without output")
            case .failed, .cancelled:
                throw JobError.decryptFailed(job.message ?? job.state.title)
            case .running, .ready, .importing:
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw JobError.timeout("decrypt")
    }

    static func fetchAndDecrypt(_ target: String, onProgress: @escaping ProgressHandler) async throws -> URL {
        let app = try await resolveApp(target)
        await onProgress("Resolved \(app.trackName) (\(app.bundleId))", 0)
        let ipa = try await fetch(app: app, onProgress: onProgress)
        await onProgress("Downloaded — starting decrypt", 70)
        return try await decrypt(ipaURL: ipa, onProgress: onProgress)
    }

    private static func extractAdamID(from urlString: String) -> Int? {
        if let regex = try? NSRegularExpression(pattern: #"/id(\d+)"#),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range(at: 1), in: urlString) {
            return Int(urlString[range])
        }
        return nil
    }
}
