import Combine
import Foundation

/// Minimal stub: Assassin restores the user's VPN via Shortcuts after installs.
/// APP keeps the same call sites without shipping that UX yet.
@MainActor
final class VPNReconnectCoordinator: ObservableObject {
    static let shared = VPNReconnectCoordinator()

    func beginDeviceWork() {}

    func deviceWorkFinished(restoreVPN: Bool) async {
        _ = restoreVPN
    }

    func testShortcut() async {}
}
