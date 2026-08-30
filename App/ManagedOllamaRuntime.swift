import AppKit
import CryptoKit
import Foundation

/// How far an install has got and what it is doing, reported so the window can
/// show a stage rather than only a spinner.
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
/// The copy of Ollama kept inside the app's own support folder. It is separate
/// from any system wide install, and it is started and stopped by the app.
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
        // The child is given a fixed environment rather than a copy of Rank &
        // Folder's own. Ollama reads more than a dozen OLLAMA_ variables, so an
        // inherited environment could move the model directory, widen the
        // origins the local server accepts, or change how it binds, none of
        // which the person chose here. Only the variables below are passed,
        // and nothing else in the launching environment reaches the child.
        var environment: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "OLLAMA_HOST": "127.0.0.1:11434",
            "OLLAMA_ORIGINS": "http://127.0.0.1:11434",
            "OLLAMA_MODELS": ManagedRuntimeInstaller.modelsDirectory.path,
            "OLLAMA_NO_CLOUD": "1",
            "OLLAMA_KEEP_ALIVE": "0"
        ]
        if let temporaryDirectory = ProcessInfo.processInfo.environment["TMPDIR"] {
            environment["TMPDIR"] = temporaryDirectory
        }
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

/// Every way installing or starting the managed runtime can fail, including the
/// checks that refuse a download whose checksum or archive contents are wrong.
enum ManagedRuntimeError: LocalizedError {
    case unsupportedMac
    case invalidDownload
    case checksumMismatch
    case unsafeArchive
    case executableMissing
    case signatureInvalid
    case identityChanged
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
        case .identityChanged:
            "The Ollama program in Rank & Folder's support folder is no longer the one that was installed, so it was not run. Remove the managed runtime in Models and install it again."
        case .notInstalled:
            "The Rank & Folder-managed Ollama runtime is not installed."
        case .startFailed:
            "The local model runner stopped before it became ready."
        case .startTimedOut:
            "The local model runner did not become ready within 30 seconds."
        }
    }
}

/// Allows the download to follow a redirect only to the hosts that serve release
/// assets, so a redirect cannot move the download to an arbitrary server.
private final class RuntimeDownloadDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    // One list, shared with the final-response check in the installer. Two
    // copies of a host allowlist can drift apart, and the copy that is missed
    // is the one that decides where a download may come from.
    private let permittedHosts = ManagedRuntimeInstaller.permittedDownloadHosts

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

    /// The only hosts a runtime download may come from, whether as the first
    /// request, as a redirect target, or as the address that finally answered.
    static let permittedDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "github-releases.githubusercontent.com"
    ]

    /// Where the code directory hash of the installed program is remembered, so
    /// a later launch can tell that the program on disk is still the one that
    /// arrived in the checksum verified archive.
    private static let pinnedIdentityKey = "rankFolderManagedRuntimeCodeIdentity.v1"

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
              permittedDownloadHosts.contains(finalHost),
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
            try requirePinnedIdentity(of: executable)
            return executable
        }
        throw ManagedRuntimeError.executableMissing
    }

    /// Confirms that the program about to be launched is the same one that was
    /// installed from the checksum verified archive.
    ///
    /// A valid signature alone only proves a program has not changed since it
    /// was signed, and anything on this Mac that can write to the support
    /// folder can also sign a replacement. Recording the code directory hash at
    /// install time and requiring it again here is what ties every later launch
    /// back to the archive whose checksum was checked.
    ///
    /// A runtime installed before this check existed has nothing recorded. Its
    /// current hash is adopted rather than refused, because refusing would
    /// discard a working install and force a fresh download. Removing and
    /// reinstalling the runtime from the Models window records a hash that is
    /// tied to the verified archive.
    private static func requirePinnedIdentity(of executable: URL) throws {
        let identity = try codeDirectoryIdentity(at: executable)
        let defaults = UserDefaults.standard
        guard let recorded = defaults.string(forKey: pinnedIdentityKey) else {
            defaults.set(identity, forKey: pinnedIdentityKey)
            return
        }
        guard recorded == identity else {
            throw ManagedRuntimeError.identityChanged
        }
    }

    private static func recordPinnedIdentity(of executable: URL) throws {
        let identity = try codeDirectoryIdentity(at: executable)
        UserDefaults.standard.set(identity, forKey: pinnedIdentityKey)
    }

    private static func forgetPinnedIdentity() {
        UserDefaults.standard.removeObject(forKey: pinnedIdentityKey)
    }

    /// The code directory hash macOS records for a signed program, paired with
    /// the release it was recorded for so that a pinned hash from one version
    /// can never satisfy another.
    private static func codeDirectoryIdentity(at executable: URL) throws -> String {
        // codesign writes its description to standard error, so both streams
        // are captured here.
        let description: String
        do {
            description = try runTool(
                "/usr/bin/codesign",
                arguments: ["--display", "--verbose=2", executable.path],
                captureOutput: true,
                captureStandardError: true
            )
        } catch {
            // A program codesign cannot describe is one Rank & Folder cannot
            // recognize later, which is a signature problem rather than an
            // archive problem.
            throw ManagedRuntimeError.signatureInvalid
        }
        guard let line = description
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("CDHash=") }) else {
            throw ManagedRuntimeError.signatureInvalid
        }
        let hash = line.dropFirst("CDHash=".count).lowercased()
        guard hash.count >= 40, hash.allSatisfy(\.isHexDigit) else {
            throw ManagedRuntimeError.signatureInvalid
        }
        return "\(releaseVersion):\(hash)"
    }

    private static func findExecutable(in directory: URL) throws -> URL {
        let manager = FileManager.default
        // Hidden entries are enumerated too. The symbolic link check below is a
        // safety check, and an entry that escapes the install directory is no
        // less dangerous for having a name that begins with a period.
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
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
            // The recorded identity describes a program that no longer exists.
            // Leaving it behind would make the next install look like a
            // mismatch instead of a fresh, verified one.
            forgetPinnedIdentity()
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
            options: []
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
            // This is the one moment the program is known to have come from the
            // archive whose checksum was just checked, so it is the only moment
            // its identity may be recorded.
            try recordPinnedIdentity(of: executable)
        } catch {
            try? manager.removeItem(at: installationDirectory)
            forgetPinnedIdentity()
            throw ManagedRuntimeError.signatureInvalid
        }
        if manager.fileExists(atPath: compatibleInstallationDirectory.path) {
            try? manager.removeItem(at: compatibleInstallationDirectory)
        }
    }

    /// Checks that the executable still carries a valid signature. This proves
    /// the binary has not been modified since it was signed. It does not prove
    /// who signed it, so a replacement that someone re-signed locally would
    /// also pass this check on its own. `requirePinnedIdentity(of:)` is what
    /// rejects such a replacement, by requiring the code directory hash
    /// recorded at install time. Adding a verified Developer ID requirement
    /// string here would additionally name the publisher, which pinning cannot
    /// do for a runtime adopted from an older install.
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
        captureOutput: Bool,
        captureStandardError: Bool = false
    ) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = captureOutput ? pipe : FileHandle.nullDevice
        task.standardError = captureStandardError ? pipe : FileHandle.nullDevice
        try task.run()
        let capturing = captureOutput || captureStandardError
        let data = capturing ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw ManagedRuntimeError.unsafeArchive }
        guard capturing else { return "" }
        guard data.count <= 2_000_000 else { throw ManagedRuntimeError.unsafeArchive }
        return String(decoding: data, as: UTF8.self)
    }
}
