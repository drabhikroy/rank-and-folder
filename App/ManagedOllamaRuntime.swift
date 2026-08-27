import AppKit
import CryptoKit
import Foundation

struct ManagedRuntimeProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case downloading
        case verifying
        case unpacking
        case starting
    }

    let phase: Phase
    let detail: String
}

@MainActor
final class ManagedOllamaRuntime: ObservableObject {
    enum State: Equatable {
        case checking
        case unavailable
        case installed
        case external(String)
        case managed(String)
        case working(ManagedRuntimeProgress)
        case failed(String)
    }

    static let shared = ManagedOllamaRuntime()

    @Published private(set) var state: State = .checking
    private var process: Process?
    private var operation: Task<Void, Never>?

    var isInstalled: Bool { ManagedRuntimeInstaller.isInstalled }
    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    var modelsDirectory: URL { ManagedRuntimeInstaller.modelsDirectory }
    var runtimeVersion: String { ManagedRuntimeInstaller.releaseVersion }

    func refresh() {
        operation?.cancel()
        operation = Task {
            state = .checking
            do {
                let version = try await OllamaClient.version()
                try Task.checkCancellation()
                state = process?.isRunning == true ? .managed(version) : .external(version)
            } catch is CancellationError {
                return
            } catch {
                state = isInstalled ? .installed : .unavailable
            }
        }
    }

    func installAndStart() {
        guard !isWorking else { return }
        operation?.cancel()
        operation = Task {
            do {
                try await ManagedRuntimeInstaller.install { progress in
                    Task { @MainActor [weak self] in self?.state = .working(progress) }
                }
                try Task.checkCancellation()
                try await startInstalledRuntime()
            } catch is CancellationError {
                state = isInstalled ? .installed : .unavailable
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func startIfInstalled() async throws {
        if let version = try? await OllamaClient.version() {
            state = process?.isRunning == true ? .managed(version) : .external(version)
            return
        }
        guard isInstalled else {
            throw ManagedRuntimeError.notInstalled
        }
        try await startInstalledRuntime()
    }

    func cancel() {
        operation?.cancel()
        operation = nil
        if isWorking { state = isInstalled ? .installed : .unavailable }
    }

    func stop() {
        operation?.cancel()
        operation = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        if isInstalled { state = .installed }
    }

    func remove(includeModels: Bool) async {
        await removeManagedFiles(removeRuntime: true, removeModels: includeModels)
    }

    func removeManagedFiles(removeRuntime: Bool, removeModels: Bool) async {
        guard removeRuntime || removeModels else { return }
        let pendingOperation = operation
        pendingOperation?.cancel()
        operation = nil
        await pendingOperation?.value
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        do {
            try ManagedRuntimeInstaller.remove(
                removeRuntime: removeRuntime,
                removeModels: removeModels
            )
            state = isInstalled ? .installed : .unavailable
        } catch {
            state = .failed("Rank & Folder could not remove its Ollama files: \(error.localizedDescription)")
        }
    }

    private func startInstalledRuntime() async throws {
        if let version = try? await OllamaClient.version() {
            state = .external(version)
            return
        }

        state = .working(.init(phase: .starting, detail: "Starting the local model runner"))
        let executable = try ManagedRuntimeInstaller.validatedExecutableURL()
        try FileManager.default.createDirectory(
            at: ManagedRuntimeInstaller.modelsDirectory,
            withIntermediateDirectories: true
        )

        let child = Process()
        child.executableURL = executable
        child.arguments = ["serve"]
        child.currentDirectoryURL = executable.deletingLastPathComponent()
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"
        environment["OLLAMA_MODELS"] = ManagedRuntimeInstaller.modelsDirectory.path
        environment["OLLAMA_NO_CLOUD"] = "1"
        environment["OLLAMA_KEEP_ALIVE"] = "0"
        child.environment = environment
        try child.run()
        process = child

        for _ in 0..<120 {
            try Task.checkCancellation()
            if let version = try? await OllamaClient.version() {
                state = .managed(version)
                return
            }
            if !child.isRunning {
                process = nil
                throw ManagedRuntimeError.startFailed
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        child.terminate()
        process = nil
        throw ManagedRuntimeError.startTimedOut
    }
}

enum ManagedRuntimeError: LocalizedError {
    case unsupportedMac
    case invalidDownload
    case checksumMismatch
    case unsafeArchive
    case executableMissing
    case signatureInvalid
    case notInstalled
    case startFailed
    case startTimedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedMac:
            "The managed Ollama option requires macOS 14 or later. You can still install Ollama yourself."
        case .invalidDownload:
            "The Ollama download was incomplete or did not come from the expected release page. It was discarded."
        case .checksumMismatch:
            "The Ollama download did not match the published checksum. It was discarded and never opened."
        case .unsafeArchive:
            "The Ollama archive contained an unexpected path and was discarded."
        case .executableMissing:
            "The archive was verified, but the Ollama program could not be found inside it."
        case .signatureInvalid:
            "macOS could not verify the downloaded Ollama program, so Rank & Folder did not run it."
        case .notInstalled:
            "The Rank & Folder-managed Ollama runtime is not installed."
        case .startFailed:
            "The local model runner stopped before it became ready."
        case .startTimedOut:
            "The local model runner did not become ready within 30 seconds."
        }
    }
}

private final class RuntimeDownloadDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    private let permittedHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "github-releases.githubusercontent.com"
    ]

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme == "https",
              let host = url.host?.lowercased(),
              permittedHosts.contains(host) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Downloads, verifies, and unpacks a pinned Ollama release into Rank & Folder's
/// own support folder, leaving any separately installed Ollama untouched.
///
/// The install refuses to proceed at four points: a redirect leaving the
/// permitted release hosts, a file whose size is implausible, a checksum that
/// does not match the pinned value, and an archive listing an absolute or
/// upward path. The archive is unpacked into a staging folder and moved into
/// place only after those checks pass.
enum ManagedRuntimeInstaller {
    // Rank & Folder downloads only this pinned release and verifies its checksum.
    static let releaseVersion = "0.32.15"
    static let expectedSHA256 = "9ab0ac4747946620a2464054f3c44a55aa146e9fccb5c366ee18e43fd1930b90"
    static let archiveURL = URL(
        string: "https://github.com/ollama/ollama/releases/download/v0.32.15/ollama-darwin.tgz"
    )!
    static let approximateDownloadBytes: Int64 = 147_000_000

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rank & Folder", isDirectory: true)
            .appendingPathComponent("Ollama", isDirectory: true)
    }

    static var installationDirectory: URL {
        supportDirectory.appendingPathComponent("Runtime-\(releaseVersion)", isDirectory: true)
    }

    /// A second install location whose name is the literal text
    /// `Runtime-(releaseVersion)` rather than an interpolated version number.
    /// Some installed copies of Rank & Folder created the runtime there, so the
    /// path is still read when locating an executable and is removed after a
    /// successful install. Nothing new is ever written to it. Delete this
    /// property once no installed copy can still hold a runtime at that path.
    private static var compatibleInstallationDirectory: URL {
        supportDirectory.appendingPathComponent("Runtime-(releaseVersion)", isDirectory: true)
    }

    private static var installationDirectories: [URL] {
        [installationDirectory, compatibleInstallationDirectory]
    }

    static var modelsDirectory: URL {
        supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var isInstalled: Bool {
        (try? validatedExecutableURL()) != nil
    }

    static func install(
        progress: @escaping @Sendable (ManagedRuntimeProgress) -> Void
    ) async throws {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        ) else { throw ManagedRuntimeError.unsupportedMac }

        progress(.init(phase: .downloading, detail: "Downloading Ollama 0.32.15 · about 147 MB"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = RuntimeDownloadDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: archiveURL)
        request.timeoutInterval = 30 * 60
        let (downloadedURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let finalURL = http.url,
              finalURL.scheme == "https",
              let finalHost = finalURL.host?.lowercased(),
              ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com", "github-releases.githubusercontent.com"].contains(finalHost),
              downloadedFileLooksPlausible(downloadedURL) else {
            throw ManagedRuntimeError.invalidDownload
        }

        progress(.init(phase: .verifying, detail: "Checking the published SHA-256 checksum"))
        guard try sha256(of: downloadedURL) == expectedSHA256 else {
            throw ManagedRuntimeError.checksumMismatch
        }

        progress(.init(phase: .unpacking, detail: "Unpacking into Rank & Folder’s support folder"))
        let unpackTask = Task.detached(priority: .userInitiated) {
            try unpack(downloadedURL)
        }
        try await withTaskCancellationHandler {
            try await unpackTask.value
        } onCancel: {
            unpackTask.cancel()
        }
    }

    static func validatedExecutableURL() throws -> URL {
        for directory in installationDirectories where FileManager.default.fileExists(atPath: directory.path) {
            let executable = try findExecutable(in: directory)
            try verifySignature(at: executable)
            return executable
        }
        throw ManagedRuntimeError.executableMissing
    }

    private static func findExecutable(in directory: URL) throws -> URL {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { throw ManagedRuntimeError.executableMissing }

        let root = directory.standardizedFileURL.path + "/"
        var fallback: URL?
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            guard count <= 20_000 else { throw ManagedRuntimeError.unsafeArchive }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard resolved.hasPrefix(root) else { throw ManagedRuntimeError.unsafeArchive }
            }
            guard url.lastPathComponent == "ollama",
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) > 1_000_000 else { continue }
            if url.path.contains("/bin/ollama") { return url }
            fallback = fallback ?? url
        }
        guard let fallback else { throw ManagedRuntimeError.executableMissing }
        return fallback
    }

    static func remove(includeModels: Bool) throws {
        try remove(removeRuntime: true, removeModels: includeModels)
    }

    static func remove(removeRuntime: Bool, removeModels: Bool) throws {
        let manager = FileManager.default
        if removeRuntime {
            for directory in installationDirectories where manager.fileExists(atPath: directory.path) {
                try manager.removeItem(at: directory)
            }
        }
        if removeModels, manager.fileExists(atPath: modelsDirectory.path) {
            try manager.removeItem(at: modelsDirectory)
        }
    }

    private static func downloadedFileLooksPlausible(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 20_000_000 && size < 500_000_000
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Lists the archive before extracting it, so an entry with an absolute or
    /// upward path is refused while it is still only text. Extraction goes to a
    /// staging folder that is checked for symbolic links pointing outside
    /// itself, and is moved into place only after that check passes.
    private static func unpack(_ archive: URL) throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        let staging = supportDirectory.appendingPathComponent(
            ".Runtime-\(releaseVersion)-\(UUID().uuidString)",
            isDirectory: true
        )
        try manager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        let listing = try runTool("/usr/bin/tar", arguments: ["-tzf", archive.path], captureOutput: true)
        try Task.checkCancellation()
        let entries = listing.split(separator: "\n", omittingEmptySubsequences: true)
        guard !entries.isEmpty, entries.count <= 20_000 else { throw ManagedRuntimeError.unsafeArchive }
        for rawEntry in entries {
            let entry = String(rawEntry)
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.hasPrefix("/"), !components.contains(".."), !entry.contains("\0") else {
                throw ManagedRuntimeError.unsafeArchive
            }
        }

        _ = try runTool(
            "/usr/bin/tar",
            arguments: ["-xzf", archive.path, "-C", staging.path],
            captureOutput: false
        )
        try Task.checkCancellation()

        let stagedRoot = staging.standardizedFileURL.path + "/"
        if let enumerator = manager.enumerator(
            at: staging,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            var count = 0
            for case let url as URL in enumerator {
                count += 1
                guard count <= 20_000 else { throw ManagedRuntimeError.unsafeArchive }
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
                    guard resolved.hasPrefix(stagedRoot) else { throw ManagedRuntimeError.unsafeArchive }
                }
            }
        }

        if manager.fileExists(atPath: installationDirectory.path) {
            try manager.removeItem(at: installationDirectory)
        }
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: installationDirectory)
        let executable = try findExecutable(in: installationDirectory)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        do {
            try verifySignature(at: executable)
        } catch {
            try? manager.removeItem(at: installationDirectory)
            throw ManagedRuntimeError.signatureInvalid
        }
        if manager.fileExists(atPath: compatibleInstallationDirectory.path) {
            try? manager.removeItem(at: compatibleInstallationDirectory)
        }
    }

    /// Checks that the executable still carries a valid signature. This proves
    /// the binary has not been modified since it was signed. It does not prove
    /// who signed it, so a replacement that someone re-signed locally would
    /// also pass. The pinned archive checksum is what establishes publisher
    /// identity at install time. Setting `signatureRequirement` to a verified
    /// Developer ID requirement string would extend that guarantee to every
    /// later launch.
    private static func verifySignature(at executable: URL) throws {
        do {
            _ = try runTool(
                "/usr/bin/codesign",
                arguments: ["--verify", "--strict", executable.path],
                captureOutput: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ManagedRuntimeError.signatureInvalid
        }
    }

    @discardableResult
    private static func runTool(
        _ executable: String,
        arguments: [String],
        captureOutput: Bool
    ) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = captureOutput ? pipe : FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = captureOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw ManagedRuntimeError.unsafeArchive }
        guard captureOutput else { return "" }
        guard data.count <= 2_000_000 else { throw ManagedRuntimeError.unsafeArchive }
        return String(decoding: data, as: UTF8.self)
    }
}
