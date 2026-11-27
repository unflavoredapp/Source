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

enum TelegramBotClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private static func apiURL(token: String, method: String) -> URL {
        URL(string: "https://api.telegram.org/bot\(token)/\(method)")!
    }

    static func getUpdates(token: String, offset: Int, timeout: Int = 25) async throws -> [TelegramUpdate] {
        var components = URLComponents(url: apiURL(token: token, method: "getUpdates"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "timeout", value: String(timeout)),
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TelegramAPIResponse<[TelegramUpdate]>.self, from: data)
        guard decoded.ok else {
            throw URLError(.cannotParseResponse)
        }
        return decoded.result ?? []
    }

    static func sendMessage(token: String, chatID: Int64, text: String) async {
        var request = URLRequest(url: apiURL(token: token, method: "sendMessage"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "chat_id": chatID,
            "text": text,
            "disable_web_page_preview": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }

    static func sendDocument(token: String, chatID: Int64, fileURL: URL, caption: String) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiURL(token: token, method: "sendDocument"))
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
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private struct TelegramAPIResponse<T: Decodable>: Decodable {
        let ok: Bool
        let result: T?
    }
}
