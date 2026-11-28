import Foundation

enum TelegramIPARelayError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpStatus(Int, String?)
    case badResponse
    case deliveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "IPA relay is not configured. Add the VPS URL + token in Telegram Worker settings."
        case .invalidURL:
            return "IPA relay URL is invalid."
        case .httpStatus(let code, let detail):
            if let detail, !detail.isEmpty { return "Relay HTTP \(code): \(detail)" }
            return "Relay HTTP \(code)"
        case .badResponse:
            return "Relay returned an unexpected response."
        case .deliveryFailed(let detail):
            return detail
        }
    }
}

/// Uploads large IPAs to the VPS relay.
/// When the VPS has Premium channel delivery configured, the IPA is posted to a
/// private channel by your Premium account and the bot forwards it to `chatID`.
enum TelegramIPARelay {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: config)
    }()

    struct UploadResult {
        let url: URL?
        let filename: String
        let size: Int64
        let expiresIn: Int?
        let delivered: Bool
        let destination: String?
        let deliverError: String?
        let channelDelivery: Bool
    }

    static var isConfigured: Bool {
        TelegramWorkerConfig.isRelayConfigured
    }

    /// Streams `fileURL` to `PUT {base}/upload?name=…&chat_id=…` with Bearer auth.
    static func upload(
        fileURL: URL,
        chatID: Int64,
        caption: String = "",
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> UploadResult {
        guard isConfigured else { throw TelegramIPARelayError.notConfigured }

        let base = TelegramWorkerConfig.relayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let filename = fileURL.lastPathComponent
        var components = URLComponents(string: "\(base)/upload")
        var items = [
            URLQueryItem(name: "name", value: filename),
            URLQueryItem(name: "chat_id", value: String(chatID)),
        ]
        if !caption.isEmpty {
            items.append(URLQueryItem(name: "caption", value: caption))
        }
        components?.queryItems = items
        guard let uploadURL = components?.url else { throw TelegramIPARelayError.invalidURL }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(TelegramWorkerConfig.relayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        request.setValue(String(chatID), forHTTPHeaderField: "X-Chat-Id")

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > 0 {
            request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await uploadFile(request: request, fileURL: fileURL, onProgress: onProgress)
        guard let http = response as? HTTPURLResponse else { throw TelegramIPARelayError.badResponse }
        if !(200...299).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8)
            throw TelegramIPARelayError.httpStatus(http.statusCode, detail)
        }

        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["ok"] as? Bool == true
        else {
            throw TelegramIPARelayError.badResponse
        }

        let urlString = obj["url"] as? String
        let delivered = obj["delivered"] as? Bool ?? false
        let deliverError = obj["deliverError"] as? String
        if !delivered, let deliverError, !deliverError.isEmpty,
           (obj["channelDelivery"] as? Bool) == true {
            // Channel path was expected but failed — still return so caller can fall back to link.
            // Prefer surfacing soft failure via result rather than throw when a URL exists.
            _ = deliverError
        }

        return UploadResult(
            url: urlString.flatMap(URL.init(string:)),
            filename: (obj["filename"] as? String) ?? filename,
            size: (obj["size"] as? NSNumber)?.int64Value ?? size,
            expiresIn: obj["expiresIn"] as? Int,
            delivered: delivered,
            destination: obj["destination"] as? String,
            deliverError: deliverError,
            channelDelivery: obj["channelDelivery"] as? Bool ?? false
        )
    }

    private static func uploadFile(
        request: URLRequest,
        fileURL: URL,
        onProgress: ((Double) -> Void)?
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            final class Box: @unchecked Sendable {
                var observation: NSKeyValueObservation?
            }
            let box = Box()
            let task = session.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                box.observation?.invalidate()
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response else {
                    continuation.resume(throwing: TelegramIPARelayError.badResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), response))
            }
            if let onProgress {
                box.observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                    onProgress(progress.fractionCompleted)
                }
            }
            task.resume()
        }
    }
}
