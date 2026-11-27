import Combine
import Foundation
import ZIPFoundation
#if canImport(IDeviceSwift)
import IDeviceSwift
#endif

/// On-device installation through UNlicense's built-in local VPN + pairing (idevice),
/// matching AppAssassin / TetherLess NativeInstaller call shape.
@MainActor
final class NativeInstaller: ObservableObject {
    static let shared = NativeInstaller()

    static var isSelected: Bool { InstallMethod.current == .native }

    static var isStackReady: Bool {
        #if canImport(IDeviceSwift)
        return LocalDeviceVPN.extensionBundleIdentifier != nil
        #else
        return false
        #endif
    }

    static var readinessMessage: String {
        if isStackReady { return "install_native_ready".localized }
        if LocalDeviceVPN.extensionBundleIdentifier == nil {
            return "install_native_missing_tunnel".localized
        }
        return "install_native_missing_idevice".localized
    }

    enum Stage: Equatable, Hashable {
        case idle, packing, connecting, uploading, installing, done, failed(String)
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var progress: Double = 0

    var isActive: Bool {
        switch stage {
        case .packing, .connecting, .uploading, .installing: return true
        default: return false
        }
    }

    private var observer: AnyCancellable?
    private var workflowID: UUID?
    private init() {}

    enum InstallError: LocalizedError {
        case notReady(String)
        case ipaMissing
        case busy
        case message(String)

        var errorDescription: String? {
            switch self {
            case .notReady(let message): return message
            case .ipaMissing: return "sign_install_ipa_missing".localized
            case .busy: return "A native install is already running."
            case .message(let message): return message
            }
        }
    }

    /// Entry point used by `SigningInstaller` (same signature as the previous stub).
    static func install(
        ipaURL: URL,
        bundleID: String,
        name: String,
        version: String,
        onPhase: (@MainActor (SigningInstallPhase) -> Void)? = nil
    ) async throws {
        try await shared.install(
            ipaURL: ipaURL,
            bundleID: bundleID,
            name: name,
            version: version,
            onPhase: onPhase
        )
    }

    func install(
        ipaURL: URL,
        bundleID: String,
        name: String,
        version: String,
        onPhase: (@MainActor (SigningInstallPhase) -> Void)? = nil
    ) async throws {
        _ = name
        _ = version
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw InstallError.ipaMissing
        }
        guard Self.isStackReady else {
            throw InstallError.notReady(Self.readinessMessage)
        }
        guard !isActive else { throw InstallError.busy }

        #if canImport(IDeviceSwift)
        let manager = DeviceInstallationManager.shared
        let viewModel = InstallerStatusViewModel(isIdevice: true)
        let id = UUID()
        workflowID = id
        stage = .packing
        progress = 0
        onPhase?(.preparing)

        observer = viewModel.objectWillChange.sink { [weak self, weak viewModel] _ in
            DispatchQueue.main.async {
                guard let self, let viewModel, self.workflowID == id else { return }
                self.progress = viewModel.overallProgress
                switch viewModel.status {
                case .sendingManifest, .sendingPayload:
                    self.stage = .uploading
                    onPhase?(.transferring(viewModel.overallProgress))
                case .installing:
                    self.stage = .installing
                    onPhase?(.awaitingSystem)
                default:
                    break
                }
            }
        }

        manager.retainWorkflow(id)
        BackgroundKeepAlive.shared.begin(id.uuidString)
        defer {
            manager.releaseWorkflow(id)
            BackgroundKeepAlive.shared.end(id.uuidString)
            observer = nil
            workflowID = nil
        }

        var packedDir: URL?
        defer { if let packedDir { try? FileManager.default.removeItem(at: packedDir) } }

        do {
            var sendURL = ipaURL
            if let packed = try await Self.packedCopy(of: ipaURL) {
                sendURL = packed
                packedDir = packed.deletingLastPathComponent()
            }
            try Task.checkCancellation()
            stage = .connecting
            onPhase?(.connecting)
            try await manager.install(
                at: sendURL,
                viewModel: viewModel,
                suspend: bundleID == Bundle.main.bundleIdentifier,
                mode: manager.mode,
                bundleIdentifier: bundleID,
                isCurrent: { true }
            )
            progress = 1
            stage = .done
            onPhase?(.delivered)
        } catch is CancellationError {
            stage = .idle
            throw CancellationError()
        } catch {
            stage = .failed(error.localizedDescription)
            onPhase?(.failed(error.localizedDescription))
            throw error
        }
        #else
        throw InstallError.notReady(Self.readinessMessage)
        #endif
    }

    /// Compress the signer’s often-uncompressed IPA when it meaningfully shrinks.
    private static func packedCopy(of ipa: URL) async throws -> URL? {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let size = (try? fm.attributesOfItem(atPath: ipa.path)[.size] as? Int64) ?? 0
            guard size > 8_000_000 else { return nil }
            let root = fm.temporaryDirectory.appendingPathComponent(
                "native-pack-\(UUID().uuidString)",
                isDirectory: true
            )
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            do {
                let src = root.appendingPathComponent("src", isDirectory: true)
                try fm.unzipItem(at: ipa, to: src)
                let out = root.appendingPathComponent("app.ipa")
                try fm.zipItem(
                    at: src.appendingPathComponent("Payload", isDirectory: true),
                    to: out,
                    shouldKeepParent: true,
                    compressionMethod: .deflate
                )
                try? fm.removeItem(at: src)
                let newSize = (try? fm.attributesOfItem(atPath: out.path)[.size] as? Int64) ?? size
                guard newSize < size * 9 / 10 else {
                    try? fm.removeItem(at: root)
                    return nil
                }
                return out
            } catch {
                try? fm.removeItem(at: root)
                return nil
            }
        }.value
    }
}
