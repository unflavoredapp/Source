import Foundation
import SwiftUI

struct IPASource: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var subtitle: String
    /// Asset catalog name when present (e.g. `DelvekIcon`).
    var iconAsset: String?
    /// Fallback monogram when no asset (e.g. TubeVault).
    var monogram: String?
    /// Accent for monogram tile, `#RRGGBB`.
    var accentHex: String
    var catalogCount: Int
    var handle: String
    var seedTerms: [String]

    var accentColor: Color {
        Color(hex: accentHex.hasPrefix("#") ? accentHex : "#\(accentHex)")
    }

    static let defaults: [IPASource] = [
        IPASource(
            id: UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000001")!,
            name: "DELvEK",
            subtitle: "Trusted IPA Daily Uploads!",
            iconAsset: "DelvekIcon",
            monogram: nil,
            accentHex: "F5C518",
            catalogCount: 1776,
            handle: "MRZefv",
            seedTerms: ["Netflix", "YouTube", "Spotify", "Instagram", "TikTok", "Disney", "Prime Video", "Hulu"]
        ),
        IPASource(
            id: UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000002")!,
            name: "TubeVault",
            subtitle: "This repository is dedicated to premium streaming tools and utilities.",
            iconAsset: nil,
            monogram: "TubeVault",
            accentHex: "C41E3A",
            catalogCount: 420,
            handle: "TubeVault",
            seedTerms: ["Twitch", "YouTube", "VLC", "Plex", "Tubi", "Hulu", "Disney+", "Max"]
        )
    ]
}

@MainActor
final class IPASourceStore: ObservableObject {
    static let shared = IPASourceStore()

    @Published private(set) var sources: [IPASource]

    private let storageKey = "ipa_sources_v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([IPASource].self, from: data),
           !decoded.isEmpty {
            sources = decoded
        } else {
            sources = IPASource.defaults
            persist()
        }
    }

    func add(_ source: IPASource) {
        sources.append(source)
        persist()
    }

    func update(_ source: IPASource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        persist()
    }

    func remove(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        persist()
    }

    func remove(id: UUID) {
        sources.removeAll { $0.id == id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        sources.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func reset() {
        sources = IPASource.defaults
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
