import Foundation

enum TelegramIPARelayError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpStatus(Int, String?)
    case badResponse
    case missingDownloadURL

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
        case .missingDownloadURL:
            return "Relay upload succeeded but no download URL was returned."
        }
    }
}

/// Uploads large IPAs to the VPS relay and returns a public download URL.
enum TelegramIPARelay {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: config)
    }()

    struct UploadResult {
        let url: URL
        let filename: String
        let size: Int64
        let expiresIn: Int?
    }

    static var isConfigured: Bool {
        TelegramWorkerConfig.isRelayConfigured
    }

    /// Streams `fileURL` to `PUT {base}/upload?name=…` with Bearer auth.
    static func upload(
        fileURL: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> UploadResult {
        guard isConfigured else { throw TelegramIPARelayError.notConfigured }

        let base = TelegramWorkerConfig.relayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let filename = fileURL.lastPathComponent
        var components = URLComponents(string: "\(base)/upload")
        components?.queryItems = [URLQueryItem(name: "name", value: filename)]
        guard let uploadURL = components?.url else { throw TelegramIPARelayError.invalidURL }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(TelegramWorkerConfig.relayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")

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
            obj["ok"] as? Bool == true,
            let urlString = obj["url"] as? String,
            let downloadURL = URL(string: urlString)
        else {
            throw TelegramIPARelayError.missingDownloadURL
        }

        return UploadResult(
            url: downloadURL,
            filename: (obj["filename"] as? String) ?? filename,
            size: (obj["size"] as? NSNumber)?.int64Value ?? size,
            expiresIn: obj["expiresIn"] as? Int
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
