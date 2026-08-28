import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Privacy-preserving folder summary

/// A count summary of one folder. This is the only thing a model is ever shown.
/// It carries how many items there are and how they fall into categories, never
/// a file name and never any file content.
struct FolderSnapshot: Sendable {
    let itemCount: Int
    let folderCount: Int
    let categoryCounts: [String: Int]
    let extensionCounts: [String: Int]
    let taggedItemCount: Int
    let modifiedThisWeekCount: Int
    let modifiedThisMonthCount: Int
    let oldestModification: Date?
    let newestModification: Date?
    let totalFileBytes: Int64

    var promptSummary: String {
        let categories = categoryCounts
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        let extensions = FolderMetadataPromptSanitizer.summarizedExtensions(
            extensionCounts
        )
        let dateSpanDays: Int
        if let oldestModification, let newestModification {
            dateSpanDays = max(0, Calendar.current.dateComponents(
                [.day],
                from: oldestModification,
                to: newestModification
            ).day ?? 0)
        } else {
            dateSpanDays = 0
        }
        return """
        Visible items: \(itemCount)
        Folders: \(folderCount)
        Broad file categories: \(categories.isEmpty ? "none" : categories)
        Most common extensions: \(extensions.isEmpty ? "none" : extensions)
        Items with tags: \(taggedItemCount)
        Modified in last 7 days: \(modifiedThisWeekCount)
        Modified in last 30 days: \(modifiedThisMonthCount)
        Modification-date span in days: \(dateSpanDays)
        Combined file size: \(ByteCountFormatter.string(fromByteCount: totalFileBytes, countStyle: .file))
        """
    }

    var disclosureSummary: String {
        "\(itemCount) visible items · \(folderCount) folders · \(categoryCounts.count) broad file types · no filenames or file contents"
    }
}

/// Builds the count summary, after confirming the saved folder is still the one
/// that was verified.
enum FolderSnapshotBuilder {
    static func build(profile: RankFolderProfile) throws -> FolderSnapshot {
        guard profile.canSafelyReadFolderMetadata else {
            throw SuggestionValidationError.unavailable(
                "This saved folder is too old to verify safely or changed since it was added. Remove its saved layout and add the folder again before Rank & Folder reads its metadata."
            )
        }
        let folderURL = profile.folderURL
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentTypeKey,
            .tagNamesKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var folderCount = 0
        var categories: [String: Int] = [:]
        var extensions: [String: Int] = [:]
        var taggedCount = 0
        var thisWeek = 0
        var thisMonth = 0
        var oldest: Date?
        var newest: Date?
        var totalBytes: Int64 = 0
        let now = Date()

        for url in urls {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = (values?.isDirectory ?? url.hasDirectoryPath)
                && values?.isPackage != true
            if isDirectory {
                folderCount += 1
                categories["Folders", default: 0] += 1
            } else {
                let category = broadCategory(for: values?.contentType)
                categories[category, default: 0] += 1
                let fileExtension = url.pathExtension.lowercased()
                extensions[fileExtension.isEmpty ? "No extension" : fileExtension, default: 0] += 1
                totalBytes += Int64(values?.fileSize ?? 0)
            }

            if values?.tagNames?.isEmpty == false { taggedCount += 1 }
            if let modified = values?.contentModificationDate {
                let age = now.timeIntervalSince(modified)
                if age >= 0, age <= 7 * 86_400 { thisWeek += 1 }
                if age >= 0, age <= 30 * 86_400 { thisMonth += 1 }
                oldest = oldest.map { min($0, modified) } ?? modified
                newest = newest.map { max($0, modified) } ?? modified
            }
        }

        return FolderSnapshot(
            itemCount: urls.count,
            folderCount: folderCount,
            categoryCounts: categories,
            extensionCounts: extensions,
            taggedItemCount: taggedCount,
            modifiedThisWeekCount: thisWeek,
            modifiedThisMonthCount: thisMonth,
            oldestModification: oldest,
            newestModification: newest,
            totalFileBytes: totalBytes
        )
    }

    private static func broadCategory(for type: UTType?) -> String {
        guard let type else { return "Other files" }
        if type.conforms(to: .image) { return "Images" }
        if type.conforms(to: .audiovisualContent) { return "Audio and video" }
        if type.conforms(to: .pdf) { return "PDFs" }
        if type.conforms(to: .archive) { return "Archives" }
        if type.conforms(to: .sourceCode) { return "Source code" }
        if type.conforms(to: .spreadsheet) { return "Spreadsheets" }
        if type.conforms(to: .presentation) { return "Presentations" }
        if type.conforms(to: .text) { return "Text documents" }
        return "Other files"
    }
}

// MARK: - Suggestions and validation

/// One layout a model proposed, together with its stated reasoning and which
/// model produced it. Nothing here is applied until the person accepts it.
struct LayoutSuggestion: Sendable {
    let recipe: OrganizationRecipe
    let rationale: String
    let providerName: String
    let providerDetail: String
    let folderDisclosure: String
}

/// Renders a recipe as the short sentence used when describing the current
/// layout to a model.
private extension OrganizationRecipe {
    var promptDescription: String {
        let sectionText = sections.isEmpty
            ? "no sections"
            : sections.map(\.promptDescription).joined(separator: ", then ")
        let orderText = itemOrder.map(\.promptDescription).joined(separator: ", then ")
        return "sections: \(sectionText); item order: \(orderText)"
    }

    func hasSameChoices(as other: OrganizationRecipe) -> Bool {
        sections.map(\.choiceSignature) == other.sections.map(\.choiceSignature)
            && itemOrder.map(\.choiceSignature) == other.itemOrder.map(\.choiceSignature)
    }
}

/// Renders one level for a prompt, and gives it a signature used to tell two
/// suggestions apart.
private extension OrganizationLevel {
    var choiceSignature: String {
        "\(criterion.rawValue):\(direction?.rawValue ?? "finderDefault")"
    }

    var promptDescription: String {
        "\(criterion.rawValue) \(direction?.rawValue ?? "finder default")"
    }
}

// MARK: - Ollama's loopback-only connector

/// The one field read from a generate reply.
private struct OllamaGenerateResponse: Decodable {
    let response: String
}

/// The one field read from a version reply, used to confirm a service answered.
private struct OllamaVersionResponse: Decodable {
    let version: String
}

/// The installed model list, used to say which models are already downloaded.
private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let model: String?
    }
    let models: [Model]
}

private typealias OllamaRunningModelsResponse = OllamaTagsResponse

/// Refuses any redirect. The client is fixed to the loopback address, and a
/// redirect is the one way a reply could otherwise move the connection off this
/// Mac, so redirects are rejected rather than followed.
private final class LoopbackOnlySessionDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // A localhost service must never be able to forward Rank & Folder's request.
        completionHandler(OllamaLoopbackPolicy.requestAfterRedirect(request))
    }
}

/// The connection to a local Ollama service. Every request goes to the loopback
/// address, caches and cookies are disabled, and a redirect away from that
/// address is refused rather than followed.
enum OllamaClient {
    private static let baseURL = URL(string: "http://127.0.0.1:11434/api/")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        return URLSession(
            configuration: configuration,
            delegate: LoopbackOnlySessionDelegate(),
            delegateQueue: nil
        )
    }()

    private static func request(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent(path),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = method
        return request
    }

    static func version() async throws -> String {
        let (data, response) = try await limitedData(
            for: request(path: "version"),
            maximumBytes: 16_384
        )
        try validate(response)
        let rawVersion = try JSONDecoder().decode(OllamaVersionResponse.self, from: data).version
        return safeDisplayText(rawVersion, maximumBytes: 64)
    }

    static func suggest(
        snapshot: FolderSnapshot,
        model: String,
        avoiding earlierRecipes: [OrganizationRecipe] = [],
        attempt: Int = 1
    ) async throws -> LayoutSuggestion {
        let model = try validatedCatalogModel(model)
        let earlierIdeas = earlierRecipes.isEmpty
            ? "No earlier layouts have been shown."
            : earlierRecipes.enumerated().map { index, recipe in
                "Idea \(index + 1): \(recipe.promptDescription)"
            }.joined(separator: "\n")
        let prompt = """
        Choose a simple folder layout using only name, kind, fileExtension, dateModified, dateCreated, size, tags.
        Sections create headings; itemOrder controls sequence. Prefer 0-2 sections and 1-2 order rules.
        Aggregate summary (no filenames or contents):
        \(snapshot.promptSummary)
        Explain the choice in 2-4 natural sentences for a Mac user. Describe the folder pattern you noticed,
        why the chosen sections and order should make it easier to scan, and one honest limitation or tradeoff.
        Do not mention prompts, schemas, JSON, requirements, or rule-count limits.
        Follow Rank & Folder's plain-language writing rules. Do not use contractions or em or en dashes.
        This is request \(attempt). Return a layout that is meaningfully different from every earlier idea
        while still fitting the folder summary. Do not change a direction merely to appear different.
        Earlier ideas:
        \(earlierIdeas)
        Return JSON only: {"sections":[],"itemOrder":[{"criterion":"name","direction":"ascending"}],"rationale":"clear natural-language explanation"}
        """
        var request = request(path: "generate", method: "POST")
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let levelSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "criterion": [
                    "type": "string",
                    "enum": ["name", "kind", "fileExtension", "dateModified", "dateCreated", "size", "tags"]
                ],
                "direction": [
                    "type": "string",
                    "enum": ["ascending", "descending"]
                ]
            ],
            "required": ["criterion", "direction"],
            "additionalProperties": false
        ]
        let responseSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "sections": ["type": "array", "items": levelSchema, "maxItems": 3],
                "itemOrder": ["type": "array", "items": levelSchema, "minItems": 1, "maxItems": 3],
                "rationale": ["type": "string"]
            ],
            "required": ["sections", "itemOrder", "rationale"],
            "additionalProperties": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": responseSchema,
            "think": false,
            "options": ["num_ctx": 4096, "num_predict": 900, "temperature": 0.45]
        ])
        let (data, response) = try await limitedData(for: request, maximumBytes: 1_048_576)
        try validate(response)
        let content = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data).response
        let (recipe, rationale) = try SuggestionRecipeValidator.parseJSON(content)
        return LayoutSuggestion(
            recipe: recipe,
            rationale: rationale,
            providerName: "Ollama · \(model)",
            providerDetail: "Sent only to Ollama’s local endpoint; Ollama’s behavior applies",
            folderDisclosure: snapshot.disclosureSummary
        )
    }

    static func installedModels() async throws -> Set<String> {
        let (data, response) = try await limitedData(
            for: request(path: "tags"),
            maximumBytes: 2_097_152
        )
        try validate(response)
        let models = try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
        return Set(models.flatMap { [$0.name, $0.model].compactMap { $0 } })
    }

    static func runningModels() async throws -> Set<String> {
        let (data, response) = try await limitedData(
            for: request(path: "ps"),
            maximumBytes: 2_097_152
        )
        try validate(response)
        let models = try JSONDecoder().decode(OllamaRunningModelsResponse.self, from: data).models
        return Set(models.flatMap { [$0.name, $0.model].compactMap { $0 } })
    }

    static func pull(model: String, progress: @escaping @Sendable (Double?, String) -> Void) async throws {
        let model = try validatedCatalogModel(model)
        var request = request(path: "pull", method: "POST")
        request.timeoutInterval = 24 * 60 * 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response)
        var parser = OllamaPullStreamParser()
        var lastReport = Date.distantPast

        func report(_ event: OllamaPullEvent) {
            let now = Date()
            if event.isSuccess || now.timeIntervalSince(lastReport) >= 0.1 {
                lastReport = now
                let safeStatus = safeDisplayText(event.status, maximumBytes: 240)
                progress(event.fraction, safeStatus)
            }
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            if let event = try parser.append(byte) { report(event) }
        }
        if let event = try parser.finish() { report(event) }
        try parser.requireSuccessfulCompletion()
    }

    static func delete(model: String) async throws {
        guard LocalModelDescriptor.catalog.contains(where: { $0.id == model }) else {
            throw SuggestionValidationError.unavailable(
                "Rank & Folder can remove only a model it recognizes."
            )
        }
        var request = request(path: "delete", method: "DELETE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        let (_, response) = try await limitedData(for: request, maximumBytes: 65_536)
        try validate(response)
    }

    private static func limitedData(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 65_536))
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw SuggestionValidationError.invalidResponse
            }
            data.append(byte)
        }
        return (data, response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              let url = http.url,
              OllamaLoopbackPolicy.isExactLoopbackURL(url),
              (200..<300).contains(http.statusCode) else {
            throw SuggestionValidationError.unavailable(
                "Ollama did not accept the request. Finish step 1 in Models and try again."
            )
        }
    }

    private static func validatedCatalogModel(_ model: String) throws -> String {
        guard LocalModelDescriptor.supportedCatalog.contains(where: { $0.id == model }) else {
            throw SuggestionValidationError.unavailable(
                "Choose a model from Rank & Folder's catalog before continuing."
            )
        }
        return model
    }

    private static func safeDisplayText(
        _ text: String,
        maximumBytes: Int
    ) -> String {
        let printableASCII = text.utf8.filter { byte in
            byte >= 0x20 && byte <= 0x7E
        }
        return String(
            decoding: printableASCII.prefix(maximumBytes),
            as: UTF8.self
        )
    }
}

// MARK: - Suggestion sheet

@MainActor
/// Runs one suggestion request and holds its result. Every reply is checked
/// against the fixed list of criteria before it can become a layout, and a reply
/// that fails is retried rather than shown.
final class SmartSuggestionViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case suggestion(LayoutSuggestion)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var suggestions: [LayoutSuggestion] = []
    @Published private(set) var selectedSuggestionIndex = 0
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?

    func generate(profile: RankFolderProfile, ollamaModel: String) {
        generationTask?.cancel()
        let generationID = UUID()
        activeGenerationID = generationID
        let earlierRecipes = suggestions.map(\.recipe)
        state = .loading
        generationTask = Task {
            do {
                let snapshotTask = Task.detached(priority: .userInitiated) {
                    try FolderSnapshotBuilder.build(profile: profile)
                }
                let snapshot = try await withTaskCancellationHandler {
                    try await snapshotTask.value
                } onCancel: {
                    snapshotTask.cancel()
                }
                try Task.checkCancellation()
                try await ManagedOllamaRuntime.shared.startIfInstalled()
                let installedModels = try await OllamaClient.installedModels()
                let runningModels = (try? await OllamaClient.runningModels()) ?? []
                guard OllamaModelInventoryPolicy.availableModelIDs(
                    installedIDs: installedModels,
                    runningIDs: runningModels
                ).contains(ollamaModel) else {
                    throw SuggestionValidationError.unavailable(
                        "The selected model is not ready yet. Open Models, finish its download, and try again."
                    )
                }
                var differentSuggestion: LayoutSuggestion?
                var lastGenerationError: Error?
                for retry in 0..<4 {
                    do {
                        let candidate = try await OllamaClient.suggest(
                            snapshot: snapshot,
                            model: ollamaModel,
                            avoiding: earlierRecipes,
                            attempt: earlierRecipes.count + retry + 1
                        )
                        if !earlierRecipes.contains(where: {
                            $0.hasSameChoices(as: candidate.recipe)
                        }) {
                            differentSuggestion = candidate
                            break
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        lastGenerationError = error
                    }
                }
                if differentSuggestion == nil, let lastGenerationError {
                    throw SuggestionValidationError.unavailable(
                        "The model response could not be read after several attempts. \(lastGenerationError.localizedDescription) Your earlier ideas are still available."
                    )
                }
                guard let suggestion = differentSuggestion else {
                    throw SuggestionValidationError.unavailable(
                        "The model repeated an idea you already have. It could not find another useful layout for this folder. You can review the saved ideas or choose a different model."
                    )
                }
                try Task.checkCancellation()
                guard activeGenerationID == generationID else { return }
                let isFirstSuggestion = suggestions.isEmpty
                suggestions.append(suggestion)
                selectedSuggestionIndex = isFirstSuggestion ? 0 : suggestions.count - 1
                state = .suggestion(suggestion)
            } catch is CancellationError {
                guard activeGenerationID == generationID else { return }
                state = .idle
            } catch {
                guard activeGenerationID == generationID else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func selectSuggestion(at index: Int) {
        guard suggestions.indices.contains(index) else { return }
        selectedSuggestionIndex = index
        state = .suggestion(suggestions[index])
    }

    func reset() {
        cancel()
        suggestions = []
        selectedSuggestionIndex = 0
    }
    func cancel() {
        activeGenerationID = nil
        generationTask?.cancel()
        generationTask = nil
        state = .idle
    }
}

/// The window that asks a local model for a layout and shows the result for
/// review. Nothing is saved until the person accepts it.
struct SmartSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var onboarding: OnboardingStore
    let profile: RankFolderProfile
    @ObservedObject var store: ProfileStore
    @StateObject private var model = SmartSuggestionViewModel()
    @ObservedObject private var availability = ModelCenterViewModel.shared
    @State private var hasStartedInitialSuggestion = false
    @State private var resultStage = SuggestionResultStage.review

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(RankFolderPalette.coral.opacity(0.13))
                    Image(systemName: "cpu").rankFolderFont(.title2).foregroundStyle(RankFolderPalette.coral)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Layout ideas from \(selectedModelName)")
                        .rankFolderFont(.title2, weight: .semibold)
                    Text(profile.displayName).rankFolderFont(.body).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(20)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    disclosureCard
                    suggestionContent
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(26)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            availability.startMonitoring()
            availability.checkOllama(showChecking: false)
            startInitialSuggestionIfReady()
        }
        .onChange(of: availability.isConnected) { _, _ in
            startInitialSuggestionIfReady()
        }
        .onChange(of: availability.selectedModelIsInstalled) { _, _ in
            startInitialSuggestionIfReady()
        }
        .onChange(of: model.selectedSuggestionIndex) { _, _ in
            resultStage = .review
        }
        .onDisappear {
            model.reset()
            hasStartedInitialSuggestion = false
            resultStage = .review
        }
    }

    private var disclosureCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .rankFolderFont(.title3)
                .foregroundStyle(RankFolderPalette.action)
                .frame(width: 38, height: 38)
                .background(
                    RankFolderPalette.action.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Private, review first")
                    .rankFolderFont(.headline, weight: .semibold)
                Text("Counts and ranges only. Nothing is saved until you choose it.")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 6) {
                Text(methodLabel)
                    .rankFolderFont(.caption, weight: .semibold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                Button("Change model") { openWindow(id: "models") }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var suggestionContent: some View {
        switch model.state {
            case .idle:
                if availability.isConnected && availability.selectedModelIsInstalled {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Starting the layout review")
                            .rankFolderFont(.headline, weight: .semibold)
                        Text("Rank & Folder will open the first idea as soon as it is ready.")
                            .rankFolderFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .task { startInitialSuggestionIfReady() }
                } else {
                    ContentUnavailableView {
                        Label("Finish model setup", systemImage: "cpu")
                    } description: {
                        Text(modelReadinessMessage)
                    } actions: {
                        Button("Open models") { openWindow(id: "models") }
                            .buttonStyle(.borderedProminent)
                        Button("Check again") {
                            availability.checkOllama(showChecking: false)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }

            case .loading:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Creating a layout idea…").rankFolderFont(.headline, weight: .semibold)
                    Text("No file contents are being opened.")
                        .rankFolderFont(.callout)
                        .foregroundStyle(.secondary)
                    Button("Cancel") { model.cancel() }
                }
                .frame(maxWidth: .infinity, minHeight: 280)

            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not create a layout", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        model.generate(
                            profile: profile,
                            ollamaModel: availability.selectedModelID
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Choose another model") { openWindow(id: "models") }
                    if !model.suggestions.isEmpty {
                        Button("Return to saved ideas") {
                            model.selectSuggestion(at: model.selectedSuggestionIndex)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280)

        case .suggestion(let suggestion):
            suggestionResult(suggestion)
        }
    }

    private func suggestionResult(_ suggestion: LayoutSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(resultStage == .review ? "Review this idea" : "Preview this idea")
                    .rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
                Text(resultStage == .review
                    ? "See what the model chose and why. Nothing has been saved."
                    : "This preview places every visible item into the proposed grouping structure without changing your saved folder.")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
            }

            if model.suggestions.count > 1 {
                suggestionHistory
            }

            if resultStage == .review {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            SuggestionStepLabel(number: 1, title: "Suggested organization", icon: "rectangle.3.group")
                            SuggestionRecipePreview(recipe: suggestion.recipe)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            SuggestionStepLabel(number: 2, title: "Why it may help", icon: "text.bubble")
                            Text(suggestion.rationale)
                                .rankFolderFont(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Folder facts used", systemImage: "list.bullet.clipboard")
                                .rankFolderFont(.headline, weight: .semibold)
                            Text(suggestion.folderDisclosure)
                                .rankFolderFont(.callout)
                                .foregroundStyle(.secondary)
                            Label(suggestion.providerName, systemImage: "cpu")
                                .rankFolderFont(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        resultStage = .preview
                    } label: {
                        Label("Preview this layout", systemImage: "eye")
                    }
                    .buttonStyle(RankFolderPrimaryActionButtonStyle())

                    Button {
                        requestAnotherSuggestion()
                    } label: {
                        Text("Try another")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(RankFolderSecondaryActionButtonStyle())
                }
                Text("Previewing does not save or apply the layout.")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                CompactFolderPreview(
                    profile: profile,
                    recipe: suggestion.recipe,
                    heading: "Folder preview"
                )

                HStack(spacing: 10) {
                    Button("Back to idea") { resultStage = .review }
                        .buttonStyle(RankFolderSecondaryActionButtonStyle())
                    Button("Save this layout") { applySuggestion(suggestion) }
                        .buttonStyle(RankFolderPrimaryActionButtonStyle())
                }

                Text("Saving replaces this folder’s current recipe. You can edit every choice afterward.")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ideas from this session")
                .rankFolderFont(.headline, weight: .semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.suggestions.indices, id: \.self) { index in
                        Button("Idea \(index + 1)") {
                            model.selectSuggestion(at: index)
                        }
                        .buttonStyle(
                            SuggestionHistoryButtonStyle(
                                selected: index == model.selectedSuggestionIndex
                            )
                        )
                        .accessibilityValue(index == model.selectedSuggestionIndex ? "Selected" : "")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 2)
    }

    private func applySuggestion(_ suggestion: LayoutSuggestion) {
        store.update(id: profile.id, recipe: suggestion.recipe)
        SecondaryWindowStore.shared.requestedPreviewProfileID = profile.id
        NotificationCenter.default.post(name: .rankFolderSelectProfile, object: profile.id)
        NotificationCenter.default.post(name: .rankFolderShowPreview, object: profile.id)
        openWindow(id: "profiles")
        dismissWindow(id: "model-layout")
        NSApp.activate(ignoringOtherApps: true)
        AccessibilityNotification.Announcement(
            "Model layout saved for \(profile.displayName). Preview opened."
        ).post()
    }

    private func startInitialSuggestionIfReady() {
        guard !hasStartedInitialSuggestion,
              availability.isConnected,
              availability.selectedModelIsInstalled else { return }
        hasStartedInitialSuggestion = true
        resultStage = .review
        model.generate(
            profile: profile,
            ollamaModel: availability.selectedModelID
        )
    }

    private func requestAnotherSuggestion() {
        resultStage = .review
        model.generate(
            profile: profile,
            ollamaModel: availability.selectedModelID
        )
    }

    private var methodLabel: String {
        availability.isConnected
            ? "\(selectedModelName) · Local"
            : "Local model · Not ready"
    }

    private var selectedModelName: String {
        LocalModelDescriptor.catalog.first(where: { $0.id == availability.selectedModelID })?.name
            ?? availability.selectedModelID
    }

    private var modelReadinessMessage: String {
        if !availability.isConnected {
            return "Rank & Folder cannot reach Ollama yet. Open models to start it or connect an existing installation. This window will update automatically when it becomes ready."
        }
        return "\(selectedModelName) is selected but not installed. Open models to download it. This window will update automatically when the download finishes."
    }
}

/// Whether the result is being read as a list of rules or as a preview of the
/// folder under those rules.
private enum SuggestionResultStage {
    case review
    case preview
}

/// The selectable chip for one earlier suggestion in this session.
private struct SuggestionHistoryButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rankFolderFont(.callout, weight: .semibold)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(
                selected ? RankFolderPalette.accent : Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
            .overlay {
                if !selected {
                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(Capsule())
    }
}

/// A numbered heading for one step of the suggestion flow.
private struct SuggestionStepLabel: View {
    let number: Int
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .rankFolderFont(.callout, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(RankFolderPalette.accent, in: Circle())
                .accessibilityHidden(true)
            Label(title, systemImage: icon)
                .rankFolderFont(.title3, weight: .semibold)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title)")
    }
}

/// Lists a suggested recipe as plain sentences, so the rules can be read before
/// the folder preview is opened.
private struct SuggestionRecipePreview: View {
    let recipe: OrganizationRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewArea(
                title: "Sections",
                icon: "rectangle.split.3x1",
                levels: recipe.sections,
                empty: "No sections"
            )
            Divider()
            previewArea(
                title: "Item order",
                icon: "arrow.up.arrow.down",
                levels: recipe.itemOrder,
                empty: "Name"
            )
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.08)) }
    }

    private func previewArea(
        title: String,
        icon: String,
        levels: [OrganizationLevel],
        empty: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Label(title, systemImage: icon).rankFolderFont(.headline, weight: .semibold).frame(width: 120, alignment: .leading)
            FlowLayout(spacing: 7) {
                if levels.isEmpty {
                    Text(empty).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                        if index > 0 { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        Text(levelLabel(level))
                            .rankFolderFont(.callout, weight: .medium)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private func levelLabel(_ level: OrganizationLevel) -> String {
        guard let direction = level.direction else { return level.criterion.displayName }
        return "\(level.criterion.displayName) · \(direction.displayName(for: level.criterion))"
    }
}

/// A compact wrapping layout for recipe chips.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, max(0, x)), height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Model Center and Mac compatibility

/// What this Mac can run, read only after the person agrees. Used to say which
/// downloadable models would fit.
struct DeviceCapabilitySnapshot {
    let chip: String
    let memoryGB: Int
    let macOSVersion: String
    let freeStorageGB: Int?
}

/// Reads the chip, memory, system version, and free storage figures.
enum DeviceCapabilityService {
    static func current() -> DeviceCapabilitySnapshot {
        #if arch(arm64)
        let chip = "Apple silicon"
        #else
        let chip = "Intel"
        #endif
        let process = ProcessInfo.processInfo
        let memory = max(1, Int(process.physicalMemory / 1_073_741_824))
        let storageValues = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return DeviceCapabilitySnapshot(
            chip: chip,
            memoryGB: memory,
            macOSVersion: "macOS \(process.operatingSystemVersion.majorVersion).\(process.operatingSystemVersion.minorVersion).\(process.operatingSystemVersion.patchVersion)",
            freeStorageGB: storageValues?.volumeAvailableCapacityForImportantUsage.map {
                Int($0 / 1_000_000_000)
            }
        )
    }
}

/// One model the app knows how to offer, with what it needs and what it is good
/// at.
struct LocalModelDescriptor: Identifiable {
    static let defaultModelID = ModelRecommendationPolicy.startingModelID

    let id: String
    let name: String
    let downloadSize: String
    let approximateBytes: Int64
    let recommendedMemoryGB: Int
    let speed: String
    let license: String
    let sourceURL: URL

    /// Very small models are not offered because they do not consistently
    /// return the complete layout schema. Their descriptors let Rank & Folder
    /// identify and remove installed copies.
    var isReliableForFolderLayouts: Bool {
        !["qwen3:0.6b", "gemma3:270m", "llama3.2:1b", "gemma3:1b", "qwen3:1.7b"]
            .contains(id)
    }

    var minimumMemoryGB: Int {
        switch approximateBytes {
        case ..<4_000_000_000: 8
        case ..<8_000_000_000: 16
        case ..<12_000_000_000: 24
        default: 48
        }
    }

    var requiredFreeStorageGB: Int {
        // Ollama may temporarily need both downloaded chunks and the completed
        // model. Leave another gigabyte for manifests and normal app work.
        Int(ceil(Double(approximateBytes) * 2 / 1_000_000_000)) + 1
    }

    func fits(_ device: DeviceCapabilitySnapshot) -> Bool {
        guard device.memoryGB >= minimumMemoryGB else { return false }
        if let freeStorageGB = device.freeStorageGB,
           freeStorageGB < requiredFreeStorageGB { return false }
        return true
    }

    func recommendationScore(on device: DeviceCapabilitySnapshot?) -> Int {
        let taskFit: Int
        switch id {
        case "qwen3:8b": taskFit = 112
        case "qwen3:4b": taskFit = 108
        case "gemma3:12b": taskFit = 106
        case "qwen3:14b": taskFit = 104
        case "gemma3:4b": taskFit = 101
        case "llama3.2:3b": taskFit = 98
        default: taskFit = 88
        }
        guard let device else { return taskFit - minimumMemoryGB }
        let comfortableBonus = device.memoryGB >= recommendedMemoryGB ? 8 : 0
        let sizePenalty = Int(approximateBytes / 3_000_000_000)
        return taskFit + comfortableBonus - sizePenalty
    }

    var bestFor: String {
        if id.contains("0.6b") || id.contains("270m") {
            return "Quick checks on straightforward folders"
        }
        if id.contains("1b") || id.contains("1.7b") {
            return "Everyday folders with a mix of common file types"
        }
        if id.contains("3b") || id.contains("4b") {
            return "Busy folders where type, date, and size all matter"
        }
        if id.contains("8b") || id.contains("12b") {
            return "Large or varied folders with several competing patterns"
        }
        return "High-memory Macs; usually more capacity than this task needs"
    }

    var benefits: [String] {
        var values: [String]
        if id.hasPrefix("qwen") {
            values = ["Built to follow structured instructions", "Can compare type, date, size, and folder counts together"]
        } else if id.hasPrefix("gemma") {
            values = ["Tends to give short explanations", "Offers several compact sizes for local use"]
        } else {
            values = ["Often gives readable explanations", "Common model family with broad local-tool support"]
        }
        if recommendedMemoryGB <= 8 {
            values[1] = "Uses less memory and normally responds faster"
        }
        return values
    }

    var drawbacks: [String] {
        var values: [String] = []
        if recommendedMemoryGB <= 8 {
            values.append("May overlook a competing pattern in a busy folder")
        } else if recommendedMemoryGB <= 16 {
            values.append("Uses more memory and responds more slowly")
        } else {
            values.append("Large download and noticeably slower response")
        }
        if license.contains("Gemma") {
            values.append("Uses Gemma terms rather than Apache 2.0")
        } else if license.contains("Llama") {
            values.append("Uses the Llama community license")
        } else {
            values.append("Still needs your review before use")
        }
        return values
    }

    var rankFolderChoiceReason: String {
        switch id {
        case "llama3.2:3b":
            "Choose this for quicker ideas on straightforward folders when a smaller download matters more than comparing every competing pattern."
        case "qwen3:4b":
            "Choose this for the best starting balance of reliable Sections and Item Order output, response time, memory use, and download size."
        case "gemma3:4b":
            "Choose this when short explanations matter most and your folders usually have one clear pattern, such as a dominant file type or date range."
        case "qwen3:8b":
            "Choose this for larger, mixed folders where file type, dates, sizes, and folder counts may point to different useful layouts."
        case "gemma3:12b":
            "Choose this when you want more explanation around a varied folder and can accept a larger download and slower response."
        case "qwen3:14b":
            "Choose this for complex, high-volume folders when comparing several competing patterns matters more than response time."
        case "gemma3:27b":
            "Choose this only on a high-memory Mac when detailed explanations are worth a very large download for this focused task."
        case "qwen3:30b":
            "Choose this only for unusually complex folders on a high-memory Mac; most Rank & Folder layouts do not need this much model capacity."
        default:
            "Choose this when its speed, memory, and explanation style match how you want to review folder layouts."
        }
    }

    static let catalog: [LocalModelDescriptor] = [
        LocalModelDescriptor(id: "qwen3:0.6b", name: "Qwen 3 · 0.6B", downloadSize: "523 MB", approximateBytes: 523_000_000, recommendedMemoryGB: 8, speed: "Fastest", license: "Apache 2.0", sourceURL: URL(string: "https://ollama.com/library/qwen3:0.6b")!),
        LocalModelDescriptor(id: "gemma3:270m", name: "Gemma 3 · 270M", downloadSize: "292 MB", approximateBytes: 292_000_000, recommendedMemoryGB: 8, speed: "Fastest", license: "Gemma Terms", sourceURL: URL(string: "https://ollama.com/library/gemma3:270m")!),
        LocalModelDescriptor(id: "llama3.2:1b", name: "Llama 3.2 · 1B", downloadSize: "1.3 GB", approximateBytes: 1_300_000_000, recommendedMemoryGB: 8, speed: "Very fast", license: "Llama 3.2 Community", sourceURL: URL(string: "https://ollama.com/library/llama3.2:1b")!),
        LocalModelDescriptor(id: "gemma3:1b", name: "Gemma 3 · 1B", downloadSize: "815 MB", approximateBytes: 815_000_000, recommendedMemoryGB: 8, speed: "Very fast", license: "Gemma Terms", sourceURL: URL(string: "https://ollama.com/library/gemma3:1b")!),
        LocalModelDescriptor(id: "qwen3:1.7b", name: "Qwen 3 · 1.7B", downloadSize: "1.4 GB", approximateBytes: 1_400_000_000, recommendedMemoryGB: 8, speed: "Very fast", license: "Apache 2.0", sourceURL: URL(string: "https://ollama.com/library/qwen3:1.7b")!),
        LocalModelDescriptor(id: "llama3.2:3b", name: "Llama 3.2 · 3B", downloadSize: "2.0 GB", approximateBytes: 2_000_000_000, recommendedMemoryGB: 16, speed: "Fast", license: "Llama 3.2 Community", sourceURL: URL(string: "https://ollama.com/library/llama3.2:3b")!),
        LocalModelDescriptor(id: "qwen3:4b", name: "Qwen 3 · 4B", downloadSize: "2.5 GB", approximateBytes: 2_500_000_000, recommendedMemoryGB: 16, speed: "Fast", license: "Apache 2.0", sourceURL: URL(string: "https://ollama.com/library/qwen3:4b")!),
        LocalModelDescriptor(id: "gemma3:4b", name: "Gemma 3 · 4B", downloadSize: "3.3 GB", approximateBytes: 3_300_000_000, recommendedMemoryGB: 16, speed: "Moderate", license: "Gemma Terms", sourceURL: URL(string: "https://ollama.com/library/gemma3:4b")!),
        LocalModelDescriptor(id: "qwen3:8b", name: "Qwen 3 · 8B", downloadSize: "5.2 GB", approximateBytes: 5_200_000_000, recommendedMemoryGB: 24, speed: "Slower", license: "Apache 2.0", sourceURL: URL(string: "https://ollama.com/library/qwen3:8b")!),
        LocalModelDescriptor(id: "gemma3:12b", name: "Gemma 3 · 12B", downloadSize: "8.1 GB", approximateBytes: 8_100_000_000, recommendedMemoryGB: 32, speed: "Slower", license: "Gemma Terms", sourceURL: URL(string: "https://ollama.com/library/gemma3:12b")!),
        LocalModelDescriptor(id: "qwen3:14b", name: "Qwen 3 · 14B", downloadSize: "9.3 GB", approximateBytes: 9_300_000_000, recommendedMemoryGB: 32, speed: "Slower", license: "Apache 2.0", sourceURL: URL(string: "https://ollama.com/library/qwen3:14b")!),
        LocalModelDescriptor(id: "gemma3:27b", name: "Gemma 3 · 27B", downloadSize: "17 GB", approximateBytes: 17_000_000_000, recommendedMemoryGB: 48, speed: "Slow", license: "Gemma Terms", sourceURL: URL(string: "https://ollama.com/library/gemma3:27b")!),
        LocalModelDescriptor(id: "qwen3:30b", name: "Qwen 3 · 30B", downloadSize: "19 GB", approximateBytes: 19_000_000_000, recommendedMemoryGB: 48, speed: "Slow", license: "Apache 2.0", sourceURL: URL(string: "https://ollama.com/library/qwen3:30b")!)
    ]

    static var supportedCatalog: [LocalModelDescriptor] {
        catalog.filter(\.isReliableForFolderLayouts)
    }

    static func recommendedIDs(for device: DeviceCapabilitySnapshot?) -> Set<String> {
        guard let startingChoice = supportedCatalog.first(where: { $0.id == defaultModelID }) else {
            return []
        }
        return ModelRecommendationPolicy.recommendedIDs(
            supportedIDs: Set(supportedCatalog.map(\.id)),
            memoryGB: device?.memoryGB,
            startingModelMinimumMemoryGB: startingChoice.minimumMemoryGB
        )
    }

    static func validatedSavedID(
        defaults: UserDefaults = .standard
    ) -> String {
        let fallback = defaultModelID
        guard let saved = defaults.string(forKey: "suggestions.ollamaModel"),
              supportedCatalog.contains(where: { $0.id == saved }) else {
            return fallback
        }
        return saved
    }
}

@MainActor
/// Tracks whether a local Ollama service is reachable, which models are
/// installed, and which one is selected.
final class ModelCenterViewModel: ObservableObject {
    enum OllamaState: Equatable {
        case checking
        case connected(String)
        case unavailable
    }

    static let shared = ModelCenterViewModel()

    @Published var ollamaState: OllamaState = .checking
    @Published var downloadingModel: String?
    @Published var downloadProgress: Double?
    @Published var downloadStatus = ""
    @Published var downloadError: String?
    @Published var removingModel: String?
    @Published var installedModels: Set<String> = []
    @Published var runningModels: Set<String> = []
    @Published var selectedModelID: String {
        didSet {
            guard LocalModelDescriptor.supportedCatalog.contains(where: { $0.id == selectedModelID }) else {
                selectedModelID = LocalModelDescriptor.defaultModelID
                return
            }
            UserDefaults.standard.set(selectedModelID, forKey: "suggestions.ollamaModel")
        }
    }
    private var downloadTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?
    private var activeCheckID: UUID?
    private var activeDownloadID: UUID?

    init() {
        selectedModelID = LocalModelDescriptor.validatedSavedID()
    }

    var selectedModelIsInstalled: Bool {
        availableModels.contains(selectedModelID)
    }

    var availableModels: Set<String> {
        OllamaModelInventoryPolicy.availableModelIDs(
            installedIDs: installedModels,
            runningIDs: runningModels
        )
    }

    var isConnected: Bool {
        if case .connected = ollamaState { return true }
        return false
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        checkOllama()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.checkOllama(showChecking: false, replacingActiveCheck: false)
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        activeCheckID = nil
        checkTask?.cancel()
        checkTask = nil
    }

    func checkOllama(
        showChecking: Bool = true,
        replacingActiveCheck: Bool = true
    ) {
        if activeCheckID != nil && !replacingActiveCheck { return }
        if replacingActiveCheck { checkTask?.cancel() }
        let checkID = UUID()
        activeCheckID = checkID
        if showChecking && !isConnected {
            ollamaState = .checking
        }
        checkTask = Task {
            do {
                let version = try await OllamaClient.version()
                try Task.checkCancellation()
                async let installedRequest = OllamaClient.installedModels()
                async let runningRequest = OllamaClient.runningModels()
                let models = try await installedRequest
                let running = (try? await runningRequest) ?? []
                try Task.checkCancellation()
                guard activeCheckID == checkID else { return }
                ollamaState = .connected(version)
                installedModels = models
                runningModels = running
                activeCheckID = nil
                checkTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard activeCheckID == checkID else { return }
                ollamaState = .unavailable
                installedModels = []
                runningModels = []
                activeCheckID = nil
                checkTask = nil
            }
        }
    }

    func download(_ descriptor: LocalModelDescriptor) {
        guard downloadingModel == nil else { return }
        let downloadID = UUID()
        activeDownloadID = downloadID
        downloadingModel = descriptor.id
        downloadError = nil
        downloadProgress = nil
        downloadStatus = "Starting…"
        AccessibilityNotification.Announcement(
            "Downloading \(descriptor.name)."
        ).post()
        downloadTask = Task {
            do {
                try await OllamaClient.pull(model: descriptor.id) { fraction, status in
                    Task { @MainActor in
                        guard self.activeDownloadID == downloadID else { return }
                        self.downloadProgress = fraction
                        self.downloadStatus = status
                    }
                }
                try Task.checkCancellation()
                let refreshedModels = try await OllamaClient.installedModels()
                try Task.checkCancellation()
                guard refreshedModels.contains(descriptor.id) else {
                    throw SuggestionValidationError.unavailable(
                        "Ollama finished, but the model did not appear in its installed list."
                    )
                }
                guard activeDownloadID == downloadID else { return }
                installedModels = refreshedModels
                runningModels = (try? await OllamaClient.runningModels()) ?? []
                selectedModelID = descriptor.id
                downloadingModel = nil
                downloadProgress = nil
                downloadStatus = "Downloaded"
                activeDownloadID = nil
                AccessibilityNotification.Announcement(
                    "\(descriptor.name) downloaded successfully."
                ).post()
            } catch is CancellationError {
                guard activeDownloadID == downloadID else { return }
                downloadingModel = nil
                downloadProgress = nil
                downloadStatus = "Cancelled"
                activeDownloadID = nil
                AccessibilityNotification.Announcement(
                    "Download cancelled for \(descriptor.name)."
                ).post()
            } catch {
                guard activeDownloadID == downloadID else { return }
                downloadingModel = nil
                downloadProgress = nil
                let message = "Could not download \(descriptor.name): \(error.localizedDescription)"
                downloadError = message
                activeDownloadID = nil
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    func cancelDownload() {
        let cancelledModelName = downloadingModel.flatMap { modelID in
            LocalModelDescriptor.catalog.first(where: { $0.id == modelID })?.name
        }
        activeDownloadID = nil
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModel = nil
        downloadProgress = nil
        downloadStatus = "Cancelled"
        if let cancelledModelName {
            AccessibilityNotification.Announcement(
                "Download cancelled for \(cancelledModelName)."
            ).post()
        }
    }

    func remove(_ descriptor: LocalModelDescriptor) {
        guard removingModel == nil, downloadingModel == nil else { return }
        removingModel = descriptor.id
        downloadError = nil
        Task {
            do {
                try await OllamaClient.delete(model: descriptor.id)
                let refreshedModels = try await OllamaClient.installedModels()
                installedModels = refreshedModels
                runningModels = (try? await OllamaClient.runningModels()) ?? []
                if selectedModelID == descriptor.id {
                    selectedModelID = LocalModelDescriptor.supportedCatalog.first(where: {
                        availableModels.contains($0.id)
                    })?.id ?? LocalModelDescriptor.defaultModelID
                }
                removingModel = nil
                AccessibilityNotification.Announcement(
                    "\(descriptor.name) was removed."
                ).post()
            } catch {
                let message = "Could not remove \(descriptor.name): \(error.localizedDescription)"
                downloadError = message
                removingModel = nil
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    func cancelAll() {
        activeCheckID = nil
        checkTask?.cancel()
        checkTask = nil
        cancelDownload()
        removingModel = nil
    }
}

@MainActor
/// Collects what a download would fetch so the person can review it before
/// anything is downloaded.
final class LocalDownloadReviewStore: ObservableObject {
    enum Item {
        case ollama
        case model(LocalModelDescriptor)
    }

    static let shared = LocalDownloadReviewStore()
    @Published var item: Item?
    private init() {}
}

/// The window that lists exactly what will be downloaded, where it will be put,
/// and how large it is, before a download starts.
struct LocalDownloadReviewView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var review = LocalDownloadReviewStore.shared
    @ObservedObject private var model = ModelCenterViewModel.shared
    @StateObject private var runtime = ManagedOllamaRuntime.shared

    var body: some View {
        Group {
            switch review.item {
            case .ollama: ollamaReview
            case .model(let descriptor): modelReview(descriptor)
            case nil:
                ContentUnavailableView("Nothing to review", systemImage: "arrow.down.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RankFolderBackdrop())
    }

    private var ollamaReview: some View {
        reviewLayout(
            icon: "shippingbox.fill",
            title: "Add Ollama to Rank & Folder?",
            subtitle: "A private local runner · about 147 MB",
            benefits: [
                "Runs the selected model locally on this Mac.",
                "Requires no Terminal setup and does not add an app to Applications."
            ],
            considerations: [
                "Rank & Folder downloads the pinned, signed Ollama 0.32.15 release.",
                "You can remove this private copy later from Rank & Folder."
            ],
            primaryTitle: "Download Ollama"
        ) {
            runtime.installAndStart()
            dismissWindow(id: "download-review")
        }
    }

    private func modelReview(_ descriptor: LocalModelDescriptor) -> some View {
        reviewLayout(
            icon: "cpu.fill",
            title: "Download \(descriptor.name)?",
            subtitle: "\(descriptor.downloadSize) · \(descriptor.speed) · \(descriptor.license)",
            benefits: descriptor.benefits,
            considerations: descriptor.drawbacks + ["Ollama’s model source and network behavior apply."],
            primaryTitle: "Download \(descriptor.downloadSize)"
        ) {
            model.download(descriptor)
            dismissWindow(id: "download-review")
        }
    }

    private func reviewLayout(
        icon: String,
        title: String,
        subtitle: String,
        benefits: [String],
        considerations: [String],
        primaryTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(RankFolderPalette.accent)
                            .frame(width: 58, height: 58)
                            .background(RankFolderPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title).rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
                            Text(subtitle).rankFolderFont(.body).foregroundStyle(.secondary)
                        }
                    }

                    DownloadReviewSection(
                        title: "Why it may help",
                        icon: "plus.circle.fill",
                        items: benefits
                    )
                    DownloadReviewSection(
                        title: "Before you continue",
                        icon: "info.circle.fill",
                        items: considerations
                    )

                    Label("Nothing is downloaded until you choose the primary button below.", systemImage: "hand.raised.fill")
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 540, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }

            Divider()
            HStack(spacing: 12) {
                Button("Cancel") { dismissWindow(id: "download-review") }
                    .buttonStyle(RankFolderSecondaryActionButtonStyle())
                Spacer()
                Button(primaryTitle, action: action)
                    .buttonStyle(RankFolderPrimaryActionButtonStyle())
            }
            .padding(18)
            .background(.regularMaterial)
        }
    }
}

/// One group of the download review list.
private struct DownloadReviewSection: View {
    let title: String
    let icon: String
    let items: [String]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .rankFolderFont(.title3, weight: .semibold)
                    .foregroundStyle(RankFolderPalette.accent)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "checkmark")
                            .rankFolderFont(.callout, weight: .bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(item).rankFolderFont(.body).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The window for choosing whether a local model is used, installing or
/// connecting Ollama, and picking which model to run.
struct ModelCenterView: View {
    @Environment(\.rankFolderPanelSpacing) private var panelSpacing
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var store: ProfileStore
    @ObservedObject private var model = ModelCenterViewModel.shared
    @StateObject private var runtime = ManagedOllamaRuntime.shared
    @State private var device: DeviceCapabilitySnapshot?
    @State private var pendingRemoval: LocalModelDescriptor?
    @State private var showingRuntimeRemoval = false
    @State private var isChoosingFolder = false

    private var eligibleModels: [LocalModelDescriptor] {
        LocalModelDescriptor.supportedCatalog.filter { descriptor in
            guard let device else { return true }
            return descriptor.fits(device)
        }
    }

    private var recommendedModelIDs: Set<String> {
        LocalModelDescriptor.recommendedIDs(for: device)
    }

    private var visibleModels: [LocalModelDescriptor] {
        let ranked = eligibleModels.sorted { left, right in
            let leftRecommended = recommendedModelIDs.contains(left.id)
            let rightRecommended = recommendedModelIDs.contains(right.id)
            if leftRecommended != rightRecommended { return leftRecommended }
            let leftScore = left.recommendationScore(on: device)
            let rightScore = right.recommendationScore(on: device)
            if leftScore != rightScore { return leftScore > rightScore }
            let leftIndex = LocalModelDescriptor.supportedCatalog.firstIndex { $0.id == left.id } ?? .max
            let rightIndex = LocalModelDescriptor.supportedCatalog.firstIndex { $0.id == right.id } ?? .max
            return leftIndex < rightIndex
        }
        return ranked
    }

    private var unsupportedInstalledModels: [LocalModelDescriptor] {
        LocalModelDescriptor.catalog.filter {
            !$0.isReliableForFolderLayouts && model.availableModels.contains($0.id)
        }
    }

    private var detectedEligibleModels: [LocalModelDescriptor] {
        eligibleModels.filter { model.availableModels.contains($0.id) }
    }

    private var visibleModelRowStarts: [Int] {
        Array(stride(from: 0, to: visibleModels.count, by: 2))
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24 * panelSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        modelCenterHeading
                        Spacer()
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 52, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(RankFolderPalette.action, RankFolderPalette.coral.opacity(0.76))
                            .accessibilityHidden(true)
                    }
                    modelCenterHeading
                }

                ModelStepHeader(
                    number: 1,
                    title: "Choose where Ollama runs",
                    detail: "Keep a private copy in Rank & Folder, or connect the Ollama already on this Mac.",
                    status: "Ready",
                    isComplete: true
                )
                setupLocationCard

                    ModelStepHeader(
                        number: 2,
                        title: onboarding.ollamaSetupStyle == .rankFolder
                            ? "Prepare Rank & Folder’s Ollama"
                            : "Connect to your Ollama",
                        detail: onboarding.ollamaSetupStyle == .rankFolder
                            ? "Rank & Folder keeps this runner and its models in a private support folder."
                            : "Rank & Folder checks the local Ollama service and updates this page automatically.",
                        status: ollamaRuntimeStatus,
                        isComplete: runnerReady
                    )
                    ollamaCard

                    if runnerReady {
                        ModelStepHeader(
                            number: 3,
                            title: onboarding.ollamaSetupStyle == .rankFolder
                                ? "Choose and download a model"
                                : "Choose a model",
                            detail: onboarding.ollamaSetupStyle == .rankFolder
                                ? "Rank & Folder lists only models that can reliably return a complete folder layout."
                                : "Available and currently running models are recognized automatically. Other cards provide a copyable run command.",
                            status: ollamaModelsReady ? "Ready" : "Choose one",
                            isComplete: ollamaModelsReady
                        )
                        compatibilityCard
                        if !detectedEligibleModels.isEmpty {
                            detectedModelPicker
                        }
                        if let downloadError = model.downloadError {
                            Label(downloadError, systemImage: "exclamationmark.triangle.fill")
                                .rankFolderFont(.body)
                                .foregroundStyle(.red)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        modelCatalog
                            .id("model-catalog")
                    }

                    if ollamaModelsReady {
                        modelSetupCompletionCard
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(28 * panelSpacing)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 600, minHeight: 440)
        .background(RankFolderBackdrop())
        .task {
            onboarding.suggestionMethod = .ollama
            runtime.refresh()
            model.startMonitoring()
            model.checkOllama(showChecking: false)
        }
        .onChange(of: onboarding.allowsCompatibilityCheck) { _, allowed in
            device = allowed ? DeviceCapabilityService.current() : nil
            chooseCompatibleDefaultIfNeeded()
        }
        .onChange(of: model.availableModels) { _, _ in
            selectFirstDetectedModelIfNeeded()
        }
        .onAppear {
            onboarding.suggestionMethod = .ollama
            if onboarding.allowsCompatibilityCheck {
                device = DeviceCapabilityService.current()
                chooseCompatibleDefaultIfNeeded()
            }
            selectFirstDetectedModelIfNeeded()
        }
        .onChange(of: runtime.state) { _, state in
            switch state {
            case .managed, .external:
                model.checkOllama()
            default:
                break
            }
        }
        .onDisappear { model.cancelAll() }
        .alert(
            "Remove this model?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button("Keep model", role: .cancel) { pendingRemoval = nil }
            Button("Remove model", role: .destructive) {
                guard let pendingRemoval else { return }
                model.remove(pendingRemoval)
                self.pendingRemoval = nil
            }
        } message: {
            if let pendingRemoval {
                Text(modelRemovalExplanation(for: pendingRemoval))
            }
        }
        .confirmationDialog(
            "Remove Rank & Folder’s Ollama copy?",
            isPresented: $showingRuntimeRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove runtime only", role: .destructive) {
                removeManagedRuntime(includeModels: false)
            }
            Button("Remove runtime and downloaded models", role: .destructive) {
                removeManagedRuntime(includeModels: true)
            }
            Button("Keep everything", role: .cancel) {}
        } message: {
            Text("This removes only the Ollama program and/or models stored in Rank & Folder’s Application Support folder. It does not remove folders, layouts, or a separate Ollama Desktop installation.")
        }
    }

    private var modelCenterHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local models")
                .rankFolderFont(.callout, weight: .bold)
                .tracking(1.5)
                .foregroundStyle(RankFolderPalette.accent)
            Text("Set up an optional local model")
                .rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
            Text("A local model can compare file types, dates, sizes, and folder counts before proposing an editable layout. Rank & Folder works fully without one.")
                .rankFolderFont(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ollamaRuntimeStatus: String {
        if runnerReady { return "Ready" }
        if case .checking = runtime.state { return "Checking" }
        if onboarding.ollamaSetupStyle == .rankFolder,
           case .external = runtime.state { return "Existing service found" }
        return onboarding.ollamaSetupStyle == .terminal ? "Not detected" : "Not yet"
    }

    private var runnerReady: Bool {
        switch onboarding.ollamaSetupStyle {
        case .rankFolder:
            if case .managed = runtime.state { return model.isConnected }
            return false
        case .terminal:
            return model.isConnected
        }
    }

    private var ollamaModelsReady: Bool {
        runnerReady
            && readyModel != nil
    }

    private var readyModel: LocalModelDescriptor? {
        detectedEligibleModels.first { $0.id == model.selectedModelID }
    }

    private func selectFirstDetectedModelIfNeeded() {
        guard !detectedEligibleModels.contains(where: { $0.id == model.selectedModelID }),
              let firstDetected = detectedEligibleModels.first else { return }
        model.selectedModelID = firstDetected.id
    }

    private func chooseCompatibleDefaultIfNeeded() {
        guard !eligibleModels.contains(where: { $0.id == model.selectedModelID }),
              let replacement = eligibleModels.max(by: {
                  $0.recommendationScore(on: device) < $1.recommendationScore(on: device)
              }) else { return }
        model.selectedModelID = replacement.id
    }

    private var setupLocationCard: some View {
        Grid(horizontalSpacing: 14) {
            GridRow(alignment: .top) {
                rankFolderOllamaChoice
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                existingOllamaChoice
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rankFolderOllamaChoice: some View {
        OllamaLocationChoice(
            title: "Keep it in Rank & Folder",
            detail: "No Terminal setup. The signed Ollama runner and its models stay in Rank & Folder’s private support folder.",
            note: "Adds a separate download that Rank & Folder can remove later.",
            icon: "shippingbox.fill",
            selected: onboarding.ollamaSetupStyle == .rankFolder
        ) {
            onboarding.ollamaSetupStyle = .rankFolder
            runtime.refresh()
        }
    }

    private var existingOllamaChoice: some View {
        OllamaLocationChoice(
            title: "Use my existing Ollama",
            detail: "Connect to an Ollama service already installed and running on this Mac.",
            note: "Uses its shared model library; removing a model may affect other apps.",
            icon: "terminal.fill",
            selected: onboarding.ollamaSetupStyle == .terminal
        ) {
            onboarding.ollamaSetupStyle = .terminal
            runtime.stop()
            runtime.refresh()
            model.checkOllama()
        }
    }

    private var compatibilityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer")
                        .rankFolderFont(.title3)
                        .foregroundStyle(RankFolderPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show models that fit this Mac").rankFolderFont(.title3, weight: .semibold)
                        Text(onboarding.allowsCompatibilityCheck ? "Local check allowed" : "Optional and off")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("With your permission, Rank & Folder checks this Mac’s processor, memory, macOS version, and free space. The details stay in memory and are never saved or shared.")
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Allow local compatibility check",
                        isOn: $onboarding.allowsCompatibilityCheck
                    )
                    .toggleStyle(.switch)

                    if let device {
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) { compatibilityBadges(device) }
                            VStack(alignment: .leading, spacing: 10) { compatibilityBadges(device) }
                        }
                        Text("Fit labels are conservative estimates. Actual speed depends on the model and other running apps.")
                            .rankFolderFont(.callout)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    @ViewBuilder
    private func compatibilityBadges(_ device: DeviceCapabilitySnapshot) -> some View {
        SpecBadge(title: "Processor", value: device.chip, icon: "cpu")
        SpecBadge(title: "Memory", value: "\(device.memoryGB) GB", icon: "memorychip")
        SpecBadge(title: "System", value: device.macOSVersion, icon: "laptopcomputer")
        SpecBadge(
            title: "Free space",
            value: device.freeStorageGB.map { "\($0) GB" } ?? "Unknown",
            icon: "internaldrive"
        )
    }

    private var ollamaCard: some View {
        SurfaceCard {
            if onboarding.ollamaSetupStyle == .rankFolder {
                VStack(alignment: .leading, spacing: 16) {
                    ModelCardHeading(
                        icon: "shippingbox.fill",
                        title: "Rank & Folder’s private Ollama",
                        detail: "No Terminal setup. The runner and models stay in Rank & Folder’s support folder."
                    )
                    managedRuntimeControls
                }
            } else {
                existingOllamaContent
            }
        }
    }

    @ViewBuilder
    private var existingOllamaContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModelCardHeading(
                icon: "terminal.fill",
                title: "Your existing Ollama",
                detail: runnerReady
                    ? "Rank & Folder found the local service and is checking its available and running models every two seconds."
                    : "Rank & Folder has not found a local Ollama service yet."
            )

            if runnerReady {
                HStack(spacing: 10) {
                    Label("Ollama is running", systemImage: "checkmark.circle.fill")
                        .rankFolderFont(.body, weight: .semibold)
                        .foregroundStyle(.green)
                    Text("\(model.availableModels.count) available \(model.availableModels.count == 1 ? "model" : "models") found")
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check now") {
                        runtime.refresh()
                        model.checkOllama(showChecking: false)
                    }
                }
            } else {
                Text("Use these commands only if you want Ollama managed outside Rank & Folder. Rank & Folder copies commands but never runs them for you.")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)

                TerminalInstructionRow(
                    number: 1,
                    title: "Install Ollama",
                    detail: "Official Ollama Terminal installer for macOS.",
                    command: "curl -fsSL https://ollama.com/install.sh | sh"
                )
                TerminalInstructionRow(
                    number: 2,
                    title: "Start Ollama",
                    detail: "Keep this Terminal window open while using the service.",
                    command: "ollama serve"
                )

                HStack(spacing: 12) {
                    Link("Read Ollama’s macOS instructions", destination: URL(string: "https://docs.ollama.com/macos")!)
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Checking automatically")
                        .rankFolderFont(.callout)
                        .foregroundStyle(.secondary)
                    Button("Check now") {
                        runtime.refresh()
                        model.checkOllama(showChecking: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var managedRuntimeControls: some View {
        switch runtime.state {
        case .working(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.detail).rankFolderFont(.body).foregroundStyle(.secondary)
                Button("Cancel", action: runtime.cancel)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(progress.detail)
        case .managed:
            HStack(spacing: 10) {
                Label("Stored privately for Rank & Folder", systemImage: "checkmark.circle.fill")
                    .rankFolderFont(.callout, weight: .medium)
                Button("Remove…") { showingRuntimeRemoval = true }
            }
        case .external:
            VStack(alignment: .leading, spacing: 10) {
                Label("A different Ollama service is already running", systemImage: "exclamationmark.triangle.fill")
                    .rankFolderFont(.body, weight: .semibold)
                Text("Rank & Folder cannot start its private copy on the same local address. Use the detected service instead, or quit it and check again.")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Use existing Ollama") {
                        onboarding.ollamaSetupStyle = .terminal
                        runtime.stop()
                        runtime.refresh()
                        model.checkOllama()
                    }
                    Button("Check again") { runtime.refresh() }
                }
            }
        case .installed:
            HStack(spacing: 10) {
                Button("Start Ollama") {
                    Task {
                        try? await runtime.startIfInstalled()
                        model.checkOllama()
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Remove…") { showingRuntimeRemoval = true }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .rankFolderFont(.body)
                    .foregroundStyle(.red)
                Button("Try again", action: runtime.installAndStart)
            }
        case .checking:
            ProgressView("Checking for Ollama…")
        case .unavailable:
            HStack(spacing: 10) {
                Button("Review download") {
                    LocalDownloadReviewStore.shared.item = .ollama
                    openWindow(id: "download-review")
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Check again") { runtime.refresh() }
            }
        }
    }

    private func removeManagedRuntime(includeModels: Bool) {
        Task {
            await runtime.remove(includeModels: includeModels)
            model.checkOllama()
        }
    }

    private func modelRemovalExplanation(for descriptor: LocalModelDescriptor) -> String {
        switch runtime.state {
        case .managed, .installed:
            return "This deletes \(descriptor.name) from Rank & Folder’s private model folder. You can download it again later. It does not change your folders or saved layouts."
        default:
            return "This asks the currently running Ollama service to delete \(descriptor.name). If another app uses the same Ollama model library, that app will no longer have this model either. Your folders and saved layouts are not changed."
        }
    }

    private var detectedModelPicker: some View {
        SurfaceCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    detectedModelPickerIdentity
                    Spacer(minLength: 12)
                    detectedModelMenu
                }
                VStack(alignment: .leading, spacing: 14) {
                    detectedModelPickerIdentity
                    detectedModelMenu
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RankFolderPalette.coral.opacity(0.58), lineWidth: 2)
        }
    }

    private var detectedModelPickerIdentity: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "cpu.fill")
                .rankFolderFont(.title2)
                .foregroundStyle(RankFolderPalette.coral)
                .frame(width: 42, height: 42)
                .background(
                    RankFolderPalette.coral.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose the model Rank & Folder should use")
                    .rankFolderFont(.title3, weight: .semibold)
                Text("Rank & Folder found \(detectedEligibleModels.count) supported \(detectedEligibleModels.count == 1 ? "model" : "models") on the active Ollama service. Your choice stays selected until you change it.")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detectedModelMenu: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Use for layouts")
                .rankFolderFont(.callout, weight: .semibold)
                .foregroundStyle(.secondary)
            Picker("Use for layouts", selection: $model.selectedModelID) {
                ForEach(detectedEligibleModels) { descriptor in
                    Text(model.runningModels.contains(descriptor.id)
                        ? "\(descriptor.name) · Running"
                        : "\(descriptor.name) · Available")
                        .tag(descriptor.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 210)
            .accessibilityLabel("Model to use for layouts")
            .accessibilityHint("Choose one of the models detected on the active Ollama service")
        }
    }

    private var modelCatalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelCatalogHeading

            if visibleModels.isEmpty {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No supported model fits these limits", systemImage: "externaldrive.badge.exclamationmark")
                            .rankFolderFont(.title3, weight: .semibold)
                        Text("Rank & Folder hides choices when this Mac does not have enough memory or free space for a reliable layout response. Free some storage, or turn off the local compatibility check to review the vetted catalog yourself.")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                        ForEach(visibleModelRowStarts, id: \.self) { start in
                            GridRow(alignment: .top) {
                                modelCatalogCard(visibleModels[start])
                                    .frame(maxHeight: .infinity, alignment: .top)
                                if start + 1 < visibleModels.count {
                                    modelCatalogCard(visibleModels[start + 1])
                                        .frame(maxHeight: .infinity, alignment: .top)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                    .frame(minWidth: 700)

                    VStack(spacing: 14) {
                        ForEach(visibleModels) { descriptor in
                            modelCatalogCard(descriptor)
                        }
                    }
                }
            }

            if !unsupportedInstalledModels.isEmpty {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Older model downloads")
                                .rankFolderFont(.title3, weight: .semibold)
                            Text("These small models are no longer offered because they did not reliably return Rank & Folder’s complete layout format. You can remove them to reclaim space.")
                                .rankFolderFont(.body)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(unsupportedInstalledModels) { descriptor in
                            Divider()
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(descriptor.name).rankFolderFont(.body, weight: .medium)
                                    Text(descriptor.downloadSize).rankFolderFont(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.removingModel == descriptor.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button("Remove…", role: .destructive) {
                                        pendingRemoval = descriptor
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func modelCatalogCard(_ descriptor: LocalModelDescriptor) -> some View {
        ModelCatalogRow(
            descriptor: descriptor,
            device: device,
            isRecommended: recommendedModelIDs.contains(descriptor.id),
            isSelected: model.selectedModelID == descriptor.id,
            isDownloading: model.downloadingModel == descriptor.id,
            isRemoving: model.removingModel == descriptor.id,
            progress: model.downloadingModel == descriptor.id ? model.downloadProgress : nil,
            downloadStatus: model.downloadingModel == descriptor.id ? model.downloadStatus : nil,
            ollamaConnected: model.isConnected,
            isInstalled: model.availableModels.contains(descriptor.id),
            isRunning: model.runningModels.contains(descriptor.id),
            usesTerminalCommands: onboarding.ollamaSetupStyle == .terminal,
            select: { model.selectedModelID = descriptor.id },
            download: {
                LocalDownloadReviewStore.shared.item = .model(descriptor)
                openWindow(id: "download-review")
            },
            remove: { pendingRemoval = descriptor },
            cancelDownload: { model.cancelDownload() }
        )
    }

    private var modelCatalogHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                modelCatalogHeadingText
                Spacer(minLength: 16)
                compareModelsButton
            }
            VStack(alignment: .leading, spacing: 12) {
                modelCatalogHeadingText
                compareModelsButton
            }
        }
    }

    private var modelCatalogHeadingText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(device == nil ? "Vetted model choices" : "Supported models for this Mac")
                .rankFolderFont(.title2, weight: .semibold)
            Text("Qwen 3 · 4B is Rank & Folder’s consistent starting choice when this Mac can run it.")
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var compareModelsButton: some View {
        Button {
            openWindow(id: "model-comparison")
        } label: {
            Label("Compare models", systemImage: "tablecells")
        }
        .buttonStyle(RankFolderSecondaryActionButtonStyle())
    }

    private var modelSetupCompletionCard: some View {
        SurfaceCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    completionIdentity
                    Spacer(minLength: 16)
                    completionActions
                }
                VStack(alignment: .leading, spacing: 16) {
                    completionIdentity
                    completionActions
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RankFolderPalette.accent.opacity(0.72), lineWidth: 2)
        }
        .shadow(color: RankFolderPalette.accent.opacity(0.12), radius: 18, y: 6)
    }

    private var completionIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local model setup is complete")
                .rankFolderFont(.title2, weight: .semibold)
            Text(completionDetail)
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var completionDetail: String {
        guard let readyModel else {
            return "Choose one of the supported available models above before continuing."
        }
        if readyModel.id == model.selectedModelID {
            return "\(readyModel.name) is ready. Choose a folder now, or change models above."
        }
        return "\(readyModel.name) is already installed and ready. Rank & Folder will use it if you continue now."
    }

    private var completionActions: some View {
        Button {
                if let readyModel {
                    model.selectedModelID = readyModel.id
                }
                isChoosingFolder = true
                Task { @MainActor in
                    defer { isChoosingFolder = false }
                    guard let profileID = await FolderProfileCreationCoordinator.chooseAndAdd(to: store) else { return }
                    NotificationCenter.default.post(name: .rankFolderSelectProfile, object: profileID)
                    openWindow(id: "profiles")
                    dismissWindow(id: "models")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Label(isChoosingFolder ? "Choosing folder…" : "Choose a folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(RankFolderPrimaryActionButtonStyle())
            .disabled(isChoosingFolder)
    }

}

/// A side-by-side comparison of the offered models against what this Mac can
/// run.
struct ModelComparisonView: View {
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject private var model = ModelCenterViewModel.shared
    @State private var device: DeviceCapabilitySnapshot?

    private let criterionWidth: CGFloat = 176
    private let modelWidth: CGFloat = 238
    private let headerHeight: CGFloat = 116
    private let rowHeight: CGFloat = 134

    private var criteria: [(title: String, icon: String)] {
        [
            ("Why choose it", "scope"),
            ("Good for", "folder"),
            ("Expected speed", "speedometer"),
            ("Download", "arrow.down.circle"),
            ("Suggested memory", "memorychip"),
            ("Mac fit", "desktopcomputer"),
            ("Main strength", "plus.circle"),
            ("Main limit", "info.circle"),
            ("License", "doc.text"),
            ("Current status", "checkmark.circle")
        ]
    }

    private var descriptors: [LocalModelDescriptor] {
        LocalModelDescriptor.supportedCatalog
    }

    private var recommendedIDs: Set<String> {
        LocalModelDescriptor.recommendedIDs(for: device)
    }

    var body: some View {
        VStack(spacing: 0) {
            comparisonHeader
            Divider()

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 10) {
                    comparisonLabelColumn
                    ScrollView(.horizontal) {
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            modelHeaderRow
                            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                                comparisonValueRow(criterion.title)
                            }
                        }
                        .padding(.trailing, 24)
                    }
                    .scrollIndicators(.visible)
                }
                .padding(.leading, 24)
                .padding(.vertical, 24)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(RankFolderBackdrop())
        .onAppear {
            refreshDeviceSnapshot()
            model.startMonitoring()
            model.checkOllama(showChecking: false)
        }
        .onChange(of: onboarding.allowsCompatibilityCheck) { _, _ in
            refreshDeviceSnapshot()
        }
    }

    private var comparisonHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "tablecells")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(RankFolderPalette.coral)
                .frame(width: 48, height: 48)
                .background(
                    RankFolderPalette.coral.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Compare supported models")
                    .rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
                    .accessibilityAddTraits(.isHeader)
                Text("Read down one criterion at a time. Scroll sideways to compare every vetted model.")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                Text(recommendationExplanation)
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .background(.bar)
    }

    private var recommendationExplanation: String {
        if recommendedIDs.contains(LocalModelDescriptor.defaultModelID) {
            return "Qwen 3 · 4B is Rank & Folder’s stable starting choice. Mac fit is shown separately and does not change that choice between visits."
        }
        return "This Mac does not meet the current limits for Rank & Folder’s usual Qwen 3 · 4B starting choice. Review the Mac fit row before downloading a model."
    }

    private var modelHeaderRow: some View {
        GridRow(alignment: .top) {
            ForEach(descriptors) { descriptor in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 7) {
                        Text(descriptor.name)
                            .rankFolderFont(.title3, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if recommendedIDs.contains(descriptor.id) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(RankFolderPalette.amber)
                                .accessibilityLabel("Rank & Folder starting choice")
                        }
                    }
                    if recommendedIDs.contains(descriptor.id) {
                        Text("Starting choice")
                            .rankFolderFont(.caption, weight: .semibold)
                            .foregroundStyle(RankFolderPalette.action)
                    } else {
                        Text("Alternative")
                            .rankFolderFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: modelWidth, alignment: .leading)
                .frame(height: headerHeight, alignment: .topLeading)
                .padding(12)
                .background(
                    recommendedIDs.contains(descriptor.id)
                        ? RankFolderPalette.action.opacity(0.12)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            recommendedIDs.contains(descriptor.id)
                                ? RankFolderPalette.action.opacity(0.55)
                                : Color.primary.opacity(0.08),
                            lineWidth: recommendedIDs.contains(descriptor.id) ? 2 : 1
                        )
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var comparisonLabelColumn: some View {
        VStack(spacing: 10) {
            Text("Compare by")
                .rankFolderFont(.headline, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: criterionWidth, height: headerHeight, alignment: .bottomLeading)
                .padding(12)

            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                Label(criterion.title, systemImage: criterion.icon)
                    .rankFolderFont(.headline, weight: .semibold)
                    .foregroundStyle(criterion.title == "Why choose it"
                        ? RankFolderPalette.coral
                        : Color.primary)
                    .frame(width: criterionWidth, height: rowHeight, alignment: .topLeading)
                    .padding(12)
                    .background(
                        criterion.title == "Why choose it"
                            ? RankFolderPalette.coral.opacity(0.13)
                            : RankFolderPalette.plum.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
        }
        .padding(.trailing, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
        }
        .zIndex(1)
        .accessibilityLabel("Comparison categories, fixed while models scroll")
    }

    private func comparisonValueRow(_ title: String) -> some View {
        GridRow(alignment: .top) {
            ForEach(descriptors) { descriptor in
                Text(comparisonValue(title, for: descriptor))
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: modelWidth, alignment: .leading)
                    .frame(height: rowHeight, alignment: .topLeading)
                    .padding(12)
                    .background(
                        title == "Why choose it"
                            ? RankFolderPalette.coral.opacity(0.10)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        if title == "Why choose it" {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(RankFolderPalette.coral.opacity(0.34), lineWidth: 1)
                        }
                    }
                    .accessibilityLabel("\(title) for \(descriptor.name): \(comparisonValue(title, for: descriptor))")
            }
        }
    }

    private func comparisonValue(
        _ title: String,
        for descriptor: LocalModelDescriptor
    ) -> String {
        switch title {
        case "Why choose it": descriptor.rankFolderChoiceReason
        case "Good for": descriptor.bestFor
        case "Expected speed": descriptor.speed
        case "Download": descriptor.downloadSize
        case "Suggested memory": "\(descriptor.recommendedMemoryGB) GB"
        case "Mac fit": fitDescription(for: descriptor)
        case "Main strength": descriptor.benefits.first ?? "No summary"
        case "Main limit": descriptor.drawbacks.first ?? "No summary"
        case "License": descriptor.license
        case "Current status": statusDescription(for: descriptor)
        default: "No summary"
        }
    }

    private func fitDescription(for descriptor: LocalModelDescriptor) -> String {
        guard let device else { return "Not checked" }
        guard descriptor.fits(device) else { return "Does not fit current memory or free-space limits" }
        return device.memoryGB >= descriptor.recommendedMemoryGB
            ? "Comfortable fit"
            : "Supported; may be slower"
    }

    private func statusDescription(for descriptor: LocalModelDescriptor) -> String {
        if model.selectedModelID == descriptor.id,
           model.runningModels.contains(descriptor.id) {
            return "Running and selected"
        }
        if model.selectedModelID == descriptor.id,
           model.availableModels.contains(descriptor.id) {
            return "Available and selected"
        }
        if model.runningModels.contains(descriptor.id) { return "Running" }
        if model.installedModels.contains(descriptor.id) { return "Installed" }
        if model.selectedModelID == descriptor.id { return "Selected; not installed" }
        return "Not installed"
    }

    private func refreshDeviceSnapshot() {
        device = onboarding.allowsCompatibilityCheck
            ? DeviceCapabilityService.current()
            : nil
    }
}

/// The symbol, title, and explanatory line at the top of a model setup card.
private struct ModelCardHeading: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .rankFolderFont(.title)
                .foregroundStyle(RankFolderPalette.accent)
                .frame(width: 46, height: 46)
                .background(RankFolderPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).rankFolderFont(.title2, weight: .semibold)
                Text(detail)
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One numbered terminal instruction with a command the person can copy. The app
/// copies commands and never runs them.
private struct TerminalInstructionRow: View {
    let number: Int
    let title: String
    let detail: String
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .rankFolderFont(.callout, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(RankFolderPalette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).rankFolderFont(.body, weight: .semibold)
                Text(detail).rankFolderFont(.callout).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(command)
                        .rankFolderFont(.callout, design: .monospaced)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// One of the two answers to where Ollama should live, either inside the app's
/// own support folder or in a separate installation.
private struct OllamaLocationChoice: View {
    let title: String
    let detail: String
    let note: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .rankFolderFont(.title2)
                        .foregroundStyle(RankFolderPalette.accent)
                        .frame(width: 42, height: 42)
                        .background(RankFolderPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .rankFolderFont(.title3)
                        .foregroundStyle(selected ? RankFolderPalette.accent : Color.secondary)
                }
                Text(title).rankFolderFont(.title3, weight: .semibold)
                Text(detail).rankFolderFont(.body).foregroundStyle(.secondary)
                Label(note, systemImage: "info.circle")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(
            selected ? RankFolderPalette.accent.opacity(0.10) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? RankFolderPalette.accent : Color.primary.opacity(0.09), lineWidth: selected ? 2 : 1)
        }
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

/// A numbered step in model setup, filled when the step is done.
private struct ModelStepHeader: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    let number: Int
    let title: String
    let detail: String
    let status: String
    let isComplete: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                stepIdentity
                Spacer(minLength: 12)
                Text(status)
                    .rankFolderFont(.callout, weight: .semibold)
                    .foregroundStyle(RankFolderPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RankFolderPalette.accent.opacity(0.10), in: Capsule())
            }
            stepIdentity
        }
        .accessibilityElement(children: .combine)
    }

    private var stepIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete
                        ? colorVisionMode.color(for: .success)
                        : RankFolderPalette.accent)
                if isComplete {
                    Image(systemName: "checkmark")
                        .rankFolderFont(.headline, weight: .bold)
                } else {
                    Text("\(number)")
                        .rankFolderFont(.headline, weight: .bold)
                }
            }
            .foregroundStyle(colorVisionMode.labelOnStatusFill)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).rankFolderFont(.title2, weight: .semibold)
                Text(detail).rankFolderFont(.body).foregroundStyle(.secondary)
            }
        }
    }
}


/// One small labelled figure, such as memory or download size.
private struct SpecBadge: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(RankFolderPalette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).rankFolderFont(.callout).foregroundStyle(.secondary)
                Text(value).rankFolderFont(.body, weight: .medium)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One model in the list, showing what it needs, whether it fits this Mac, and
/// whether it is already downloaded.
private struct ModelCatalogRow: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    let descriptor: LocalModelDescriptor
    let device: DeviceCapabilitySnapshot?
    let isRecommended: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let isRemoving: Bool
    let progress: Double?
    let downloadStatus: String?
    let ollamaConnected: Bool
    let isInstalled: Bool
    let isRunning: Bool
    let usesTerminalCommands: Bool
    let select: () -> Void
    let download: () -> Void
    let remove: () -> Void
    let cancelDownload: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 15) {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .rankFolderFont(.title2)
                            .foregroundStyle(isSelected ? RankFolderPalette.accent : Color.secondary)

                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(descriptor.name).rankFolderFont(.title3, weight: .semibold)
                                if isRecommended {
                                    Label("Recommended", systemImage: "star.fill")
                                        .rankFolderFont(.callout, weight: .semibold)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(RankFolderPalette.accent.opacity(0.12), in: Capsule())
                                        .foregroundStyle(RankFolderPalette.accent)
                                }
                            }
                            if let fitLabel {
                                Text(fitLabel)
                                    .rankFolderFont(.callout, weight: .semibold)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(fitTint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(fitTint)
                            }
                            Text("Useful for: \(descriptor.bestFor)")
                                .rankFolderFont(.body)
                                .foregroundStyle(.secondary)
                            Text("\(descriptor.downloadSize) · \(descriptor.speed) · \(descriptor.license)")
                                .rankFolderFont(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(descriptor.name). \(descriptor.bestFor)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint(isSelected ? "Currently selected" : "Choose this model")

                VStack(alignment: .leading, spacing: 6) {
                    Label("Why choose it in Rank & Folder", systemImage: "scope")
                        .rankFolderFont(.body, weight: .semibold)
                        .foregroundStyle(RankFolderPalette.coral)
                    Text(descriptor.rankFolderChoiceReason)
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RankFolderPalette.coral.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        modelPoints(
                            title: "Why it may help",
                            symbol: "plus.circle.fill",
                            values: descriptor.benefits
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        modelPoints(
                            title: "Keep in mind",
                            symbol: "info.circle.fill",
                            values: descriptor.drawbacks
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        modelPoints(
                            title: "Why it may help",
                            symbol: "plus.circle.fill",
                            values: descriptor.benefits
                        )
                        modelPoints(
                            title: "Keep in mind",
                            symbol: "info.circle.fill",
                            values: descriptor.drawbacks
                        )
                    }
                }

                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        modelDetailsLink
                        Spacer()
                        modelDownloadControl
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        modelDetailsLink
                        modelDownloadControl
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var modelDetailsLink: some View {
        Link("Model details and license", destination: descriptor.sourceURL)
            .rankFolderFont(.body)
            .accessibilityLabel("Model details and license for \(descriptor.name)")
    }

    @ViewBuilder
    private var modelDownloadControl: some View {
        if isDownloading {
            VStack(alignment: .leading, spacing: 7) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 150)
                        .accessibilityLabel("Downloading \(descriptor.name)")
                        .accessibilityValue(downloadAccessibilityValue)
                    Text("\(Int(progress * 100))%")
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Downloading \(descriptor.name)")
                        .accessibilityValue(downloadAccessibilityValue)
                }
                if let downloadStatus {
                    Text(downloadStatus)
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Button("Cancel download", action: cancelDownload)
                    .accessibilityLabel("Cancel download of \(descriptor.name)")
            }
        } else if isRemoving {
            ProgressView("Removing…")
                .controlSize(.small)
        } else if isInstalled {
            HStack(spacing: 10) {
                Label(
                    modelAvailabilityLabel,
                    systemImage: "checkmark.circle.fill"
                )
                .rankFolderFont(.body, weight: .medium)
                Button("Remove…", role: .destructive, action: remove)
            }
            .accessibilityElement(children: .contain)
        } else if usesTerminalCommands {
            VStack(alignment: .leading, spacing: 7) {
                Text("Run this model in Terminal")
                    .rankFolderFont(.callout, weight: .semibold)
                Text("This starts an installed copy. If the model is missing, Ollama downloads it first and then starts it.")
                    .rankFolderFont(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("ollama run \(descriptor.id)")
                        .rankFolderFont(.callout, design: .monospaced)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "ollama run \(descriptor.id)",
                            forType: .string
                        )
                    }
                }
                Text("Rank & Folder detects the model automatically when Ollama reports it as available or running.")
                    .rankFolderFont(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Download \(descriptor.downloadSize)", action: download)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!ollamaConnected || !hasEnoughStorage)
                .accessibilityLabel("Download \(descriptor.name)")
                .help(ollamaConnected
                    ? "Ask Ollama to download this model"
                    : !hasEnoughStorage
                    ? "This Mac needs more free space for the model and working room"
                    : "Finish step 1 before downloading")
        }
    }

    private var modelAvailabilityLabel: String {
        if isRunning && isSelected { return "Running and selected" }
        if isRunning { return "Running" }
        return isSelected ? "Available and selected" : "Available"
    }

    private func modelPoints(title: String, symbol: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .rankFolderFont(.body, weight: .semibold)
                .foregroundStyle(title == "Why it may help" ? RankFolderPalette.accent : Color.secondary)
            ForEach(values, id: \.self) { value in
                Text("• \(value)")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadAccessibilityValue: String {
        let status = downloadStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let progress {
            let percentage = "\(Int(progress * 100)) percent"
            guard let status, !status.isEmpty else { return percentage }
            return "\(percentage), \(status)"
        }
        guard let status, !status.isEmpty else { return "In progress" }
        return status
    }

    private var fitLabel: String? {
        guard let device else { return nil }
        if !hasEnoughStorage { return "Not enough space" }
        return device.memoryGB >= descriptor.recommendedMemoryGB
            ? "Comfortable fit"
            : "Supported · May be slower"
    }

    /// The fit label already states the outcome in words, so this tint only
    /// reinforces it. Routing through the selected color-vision palette keeps
    /// the three states distinguishable when red and orange are not.
    private var fitTint: Color {
        guard let device else { return .secondary }
        if !hasEnoughStorage { return colorVisionMode.color(for: .danger) }
        return device.memoryGB >= descriptor.recommendedMemoryGB
            ? colorVisionMode.color(for: .success)
            : colorVisionMode.color(for: .warning)
    }

    private var hasEnoughStorage: Bool {
        guard let freeStorageGB = device?.freeStorageGB else { return true }
        return freeStorageGB >= descriptor.requiredFreeStorageGB
    }
}
