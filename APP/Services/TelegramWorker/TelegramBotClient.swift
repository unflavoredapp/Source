import Foundation

struct TelegramUpdate: Decodable {
    let update_id: Int
    let message: TelegramMessage?
}

struct TelegramMessage: Decodable {
    let message_id: Int
    let text: String?
    let chat: TelegramChat
    let from: TelegramUser?
}

struct TelegramChat: Decodable {
    let id: Int64
    let type: String?
}

struct TelegramUser: Decodable {
    let id: Int64
    let username: String?
}

enum TelegramBotError: LocalizedError {
    case invalidToken
    case invalidURL
    case httpStatus(Int, String?)
    case api(Int?, String)
    case emptyResponse
    case fileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Bot token looks invalid. Paste the full token from @BotFather with no spaces."
        case .invalidURL:
            return "Could not build a Telegram API URL from this bot token."
        case .httpStatus(let code, let detail):
            if let detail, !detail.isEmpty { return "Telegram HTTP \(code): \(detail)" }
            return "Telegram HTTP \(code)"
        case .api(let code, let detail):
            if let code { return "Telegram \(code): \(detail)" }
            return detail
        case .emptyResponse:
            return "Telegram returned an empty response."
        case .fileTooLarge(let bytes):
            let mb = Double(bytes) / 1_048_576
            return String(format: "IPA is %.1f MB — Bot API caps ~50 MB. File stays on this iPhone.", mb)
        }
    }
}

enum TelegramBotClient {
    /// Bot API document uploads fail around this size.
    static let maxDocumentBytes: Int64 = 49 * 1024 * 1024

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// BotFather tokens are `digits:secret` with no whitespace.
    static func normalizedToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
    }

    static func validateToken(_ raw: String) -> Bool {
        let token = normalizedToken(raw)
        guard let colon = token.firstIndex(of: ":") else { return false }
        let id = token[..<colon]
        let secret = token[token.index(after: colon)...]
        return !id.isEmpty && id.allSatisfy(\.isNumber) && secret.count >= 20
    }

    private static func apiURL(token: String, method: String) throws -> URL {
        let token = normalizedToken(token)
        guard validateToken(token) else { throw TelegramBotError.invalidToken }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.telegram.org"
        components.path = "/bot\(token)/\(method)"
        guard let url = components.url else { throw TelegramBotError.invalidURL }
        return url
    }

    static func getUpdates(token: String, offset: Int, timeout: Int = 25) async throws -> [TelegramUpdate] {
        var components = URLComponents(
            url: try apiURL(token: token, method: "getUpdates"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "timeout", value: String(timeout)),
            URLQueryItem(name: "allowed_updates", value: #"["message"]"#),
        ]
        guard let url = components.url else { throw TelegramBotError.invalidURL }
        let (data, response) = try await session.data(from: url)
        return try decodeEnvelope([TelegramUpdate].self, data: data, response: response)
    }

    static func sendMessage(token: String, chatID: Int64, text: String) async {
        do {
            var request = URLRequest(url: try apiURL(token: token, method: "sendMessage"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "chat_id": chatID,
                "text": text,
                "disable_web_page_preview": true,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            try ensureOK(data: data, response: response)
        } catch {
            // Best-effort status replies should not kill the poll loop.
        }
    }

    /// Returns Telegram `message_id` when the photo was accepted (for later `editMessageMedia`).
    @discardableResult
    static func sendPhoto(
        token: String,
        chatID: Int64,
        jpeg: Data,
        caption: String? = nil,
        parseMode: String? = nil,
        replyMarkup: [String: Any]? = nil
    ) async -> Int? {
        do {
            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: try apiURL(token: token, method: "sendPhoto"))
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var data = Data()
            func appendField(_ name: String, _ value: String) {
                data.append("--\(boundary)\r\n".data(using: .utf8)!)
                data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                data.append("\(value)\r\n".data(using: .utf8)!)
            }
            appendField("chat_id", String(chatID))
            if let caption, !caption.isEmpty {
                appendField("caption", caption)
            }
            if let parseMode, !parseMode.isEmpty {
                appendField("parse_mode", parseMode)
            }
            if let replyMarkup,
               let markupData = try? JSONSerialization.data(withJSONObject: replyMarkup),
               let markupString = String(data: markupData, encoding: .utf8) {
                appendField("reply_markup", markupString)
            }
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"photo\"; filename=\"card.jpg\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            data.append(jpeg)
            data.append("\r\n".data(using: .utf8)!)
            data.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = data
            let (responseData, response) = try await session.data(for: request)
            let message = try decodeEnvelope(TelegramMessageID.self, data: responseData, response: response)
            return message.message_id
        } catch {
            // Fall back to caption-only text if photo upload fails.
            if let caption, !caption.isEmpty {
                await sendMessage(token: token, chatID: chatID, text: caption)
            }
            return nil
        }
    }

    /// Updates an existing sharp-card photo in place (one dynamic message).
    @discardableResult
    static func editMessageMedia(
        token: String,
        chatID: Int64,
        messageID: Int,
        jpeg: Data,
        caption: String? = nil,
        parseMode: String? = nil,
        replyMarkup: [String: Any]? = nil
    ) async -> Bool {
        do {
            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: try apiURL(token: token, method: "editMessageMedia"))
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var media: [String: Any] = [
                "type": "photo",
                "media": "attach://card",
            ]
            if let caption, !caption.isEmpty {
                media["caption"] = caption
            }
            if let parseMode, !parseMode.isEmpty {
                media["parse_mode"] = parseMode
            }
            let mediaJSON = try JSONSerialization.data(withJSONObject: media)
            let mediaString = String(data: mediaJSON, encoding: .utf8) ?? "{}"

            var data = Data()
            func appendField(_ name: String, _ value: String) {
                data.append("--\(boundary)\r\n".data(using: .utf8)!)
                data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                data.append("\(value)\r\n".data(using: .utf8)!)
            }
            appendField("chat_id", String(chatID))
            appendField("message_id", String(messageID))
            appendField("media", mediaString)
            if let replyMarkup,
               let markupData = try? JSONSerialization.data(withJSONObject: replyMarkup),
               let markupString = String(data: markupData, encoding: .utf8) {
                appendField("reply_markup", markupString)
            }
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"card\"; filename=\"card.jpg\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            data.append(jpeg)
            data.append("\r\n".data(using: .utf8)!)
            data.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = data
            let (responseData, response) = try await session.data(for: request)
            try ensureOK(data: responseData, response: response)
            return true
        } catch {
            return false
        }
    }

    static func sendDocument(token: String, chatID: Int64, fileURL: URL, caption: String) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > maxDocumentBytes {
            throw TelegramBotError.fileTooLarge(size)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: try apiURL(token: token, method: "sendDocument"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        func appendField(_ name: String, _ value: String) {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("chat_id", String(chatID))
        appendField("caption", caption)

        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"document\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = data
        let (responseData, response) = try await session.data(for: request)
        try ensureOK(data: responseData, response: response)
    }

    private struct TelegramAPIResponse<T: Decodable>: Decodable {
        let ok: Bool
        let result: T?
        let description: String?
        let error_code: Int?
    }

    private struct TelegramMessageID: Decodable {
        let message_id: Int
    }

    private struct TelegramOKOnly: Decodable {
        let ok: Bool
        let description: String?
        let error_code: Int?
    }

    private static func decodeEnvelope<T: Decodable>(
        _ type: T.Type,
        data: Data,
        response: URLResponse
    ) throws -> T {
        if data.isEmpty { throw TelegramBotError.emptyResponse }
        if let envelope = try? JSONDecoder().decode(TelegramAPIResponse<T>.self, from: data) {
            if envelope.ok, let result = envelope.result {
                return result
            }
            if !envelope.ok {
                throw TelegramBotError.api(envelope.error_code, envelope.description ?? "Request failed")
            }
        }
        throw mapTransportError(data: data, response: response)
    }

    private static func ensureOK(data: Data, response: URLResponse) throws {
        if data.isEmpty { throw TelegramBotError.emptyResponse }
        if let envelope = try? JSONDecoder().decode(TelegramOKOnly.self, from: data) {
            if envelope.ok { return }
            throw TelegramBotError.api(envelope.error_code, envelope.description ?? "Request failed")
        }
        throw mapTransportError(data: data, response: response)
    }

    private static func mapTransportError(data: Data, response: URLResponse) -> Error {
        let detail = String(data: data, encoding: .utf8)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return TelegramBotError.httpStatus(http.statusCode, detail)
        }
        return TelegramBotError.api(nil, detail ?? "Unexpected Telegram response")
    }
}
