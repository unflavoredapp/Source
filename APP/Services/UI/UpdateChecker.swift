import Foundation
import UIKit

struct AppReleaseAsset: Decodable, Sendable {
    let name: String
    let size: Int64
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
    }
}

struct AppRelease: Decodable, Identifiable, Sendable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let prerelease: Bool
    let draft: Bool
    let htmlURL: URL
    let assets: [AppReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case body
        case prerelease
        case draft
        case assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }
}

/// Lightweight feed published at https://unlicense.cc/updates (JSON).
private struct UnlicenseUpdateFeed: Decodable {
    let version: String
    let url: URL?
    let html_url: URL?
    let notes: String?
    let body: String?
    let ipa: URL?
    let name: String?

    var pageURL: URL {
        html_url ?? url ?? URL(string: "https://unlicense.cc/updates")!
    }

    var asRelease: AppRelease {
        let tag = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        var assets: [AppReleaseAsset] = []
        if let ipa {
            assets.append(AppReleaseAsset(name: ipa.lastPathComponent, size: 0, browserDownloadURL: ipa))
        }
        return AppRelease(
            id: tag.hashValue,
            tagName: tag,
            name: name ?? "UNlicense \(tag)",
            body: notes ?? body,
            prerelease: false,
            draft: false,
            htmlURL: pageURL,
            assets: assets
        )
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(String, URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var releases: [AppRelease] = []
    @Published private(set) var lastCheckedAt: Date?

    /// Primary update feed (JSON preferred). Opens in browser as fallback.
    private let updatesFeed = URL(string: "https://unlicense.cc/updates")!
    private let lastCheckKey = "APP.update.lastCheckAt"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var latestRelease: AppRelease? {
        releases.first
    }

    var changelog: [AppRelease] {
        let current = currentVersion
        return Array(releases.prefix { Self.isNewer($0.version, than: current) })
    }

    var ipaAsset: AppReleaseAsset? {
        guard let latest = latestRelease else { return nil }
        return latest.assets.first { $0.name.lowercased().hasSuffix(".ipa") } ?? latest.assets.first
    }

    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking

        var request = URLRequest(url: updatesFeed)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UNlicense/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("no response")
                return
            }
            guard (200...299).contains(http.statusCode) else {
                state = .failed("HTTP \(http.statusCode)")
                return
            }

            let visible = try decodeReleases(from: data)
            releases = visible
            lastCheckedAt = Date()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            guard let latest = visible.first else {
                state = .failed("no release found")
                return
            }

            if Self.isNewer(latest.version, than: currentVersion) {
                state = .available(latest.version, latest.htmlURL)
            } else {
                state = .upToDate(latest.version)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func autoCheckIfNeeded() async {
        guard state == .idle else { return }
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 6 * 3600 {
            return
        }
        await check()
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        if case .failed = state {
            state = .idle
        }
    }

    func openReleasesPage() {
        UIApplication.shared.open(updatesFeed)
    }

    private func decodeReleases(from data: Data) throws -> [AppRelease] {
        let decoder = JSONDecoder()
        // GitHub Releases array
        if let list = try? decoder.decode([AppRelease].self, from: data) {
            return list.filter { !$0.draft && !$0.prerelease }
        }
        // Single GitHub release object
        if let one = try? decoder.decode(AppRelease.self, from: data), !one.draft {
            return [one]
        }
        // unlicense.cc feed
        if let feed = try? decoder.decode(UnlicenseUpdateFeed.self, from: data) {
            return [feed.asRelease]
        }
        throw URLError(.cannotParseResponse)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
