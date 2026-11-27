import Foundation

/// Keeps the process alive during native installs (full Assassin audio keep-alive can land later).
@MainActor
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()
    static var enabled: Bool { true }

    private var holds = Set<String>()

    func start(_ id: String) {
        holds.insert(id)
    }

    func stop(_ id: String) {
        holds.remove(id)
    }

    func begin(_ id: String) { start(id) }
    func end(_ id: String) { stop(id) }
}
