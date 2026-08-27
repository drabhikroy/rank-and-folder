import Foundation

enum ModelRecommendationPolicy {
    static let startingModelID = "qwen3:4b"

    static func recommendedIDs(
        supportedIDs: Set<String>,
        memoryGB: Int?,
        startingModelMinimumMemoryGB: Int
    ) -> Set<String> {
        guard supportedIDs.contains(startingModelID) else { return [] }
        if let memoryGB, memoryGB < startingModelMinimumMemoryGB { return [] }
        return [startingModelID]
    }
}

enum OllamaModelInventoryPolicy {
    static func availableModelIDs(
        installedIDs: Set<String>,
        runningIDs: Set<String>
    ) -> Set<String> {
        installedIDs.union(runningIDs)
    }
}

/// Converts untrusted filename extensions into a small, aggregate-only prompt line.
/// Only short lowercase ASCII extensions are retained; all other keys are bucketed.
enum FolderMetadataPromptSanitizer {
    static func summarizedExtensions(
        _ counts: [String: Int],
        maximumTypes: Int = 10
    ) -> String {
        let known = counts.filter { key, _ in
            key == "No extension"
                || key.range(
                    of: "^[a-z0-9]{1,12}$",
                    options: .regularExpression
                ) != nil
        }
        let omittedTypeCount = counts.count - known.count
        var parts = known
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedStandardCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(max(0, maximumTypes))
            .map { "\($0.key): \($0.value)" }
        if omittedTypeCount > 0 {
            parts.append("Other extensions: \(omittedTypeCount) types")
        }
        return parts.joined(separator: ", ")
    }
}

private struct GeneratedRecipe: Decodable {
    struct Level: Decodable {
        let criterion: String
        let direction: String?
    }

    let sections: [Level]
    let itemOrder: [Level]
    let rationale: String?

    private enum CodingKeys: String, CodingKey {
        case sections
        case itemOrder
        case groupBy
        case sortBy
        case rationale
        case reason
        case explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([Level].self, forKey: .sections)
            ?? container.decodeIfPresent([Level].self, forKey: .groupBy)
            ?? []
        itemOrder = try container.decodeIfPresent([Level].self, forKey: .itemOrder)
            ?? container.decodeIfPresent([Level].self, forKey: .sortBy)
            ?? []
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
            ?? container.decodeIfPresent(String.self, forKey: .reason)
            ?? container.decodeIfPresent(String.self, forKey: .explanation)
    }
}

enum SuggestionValidationError: LocalizedError {
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The model did not return usable Sections and Item Order choices. Try again or choose a different model."
        case .unavailable(let reason): reason
        }
    }
}

/// Treats every model response as untrusted data and emits only supported recipe types.
enum SuggestionRecipeValidator {
    static let maximumSuggestedLevelsPerArea = 3
    static let maximumRationaleCharacters = 900

    /// Turns a model response into a recipe Rank & Folder is willing to store.
    ///
    /// The response is untrusted text. It is size limited before parsing, then
    /// narrowed to the outermost brace pair, then decoded. Every criterion is
    /// matched against a fixed list, duplicates are dropped, levels are capped,
    /// and an empty item order is replaced with a name sort. A response that
    /// yields nothing usable raises rather than producing a partial recipe.
    static func parseJSON(_ text: String) throws -> (OrganizationRecipe, String) {
        guard text.utf8.count <= 1_048_576,
              let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            throw SuggestionValidationError.invalidResponse
        }
        let json = String(text[firstBrace...lastBrace])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = json.data(using: .utf8),
              let generated = try? decoder.decode(GeneratedRecipe.self, from: data) else {
            throw SuggestionValidationError.invalidResponse
        }

        let sections = validate(
            generated.sections,
            maximum: maximumSuggestedLevelsPerArea
        )
        var itemOrder = validate(
            generated.itemOrder,
            maximum: maximumSuggestedLevelsPerArea
        )
        guard !sections.isEmpty || !itemOrder.isEmpty else {
            throw SuggestionValidationError.invalidResponse
        }
        if itemOrder.isEmpty {
            itemOrder = [
                OrganizationLevel(criterion: .name, direction: .ascending)
            ]
        }
        let modelRationale = generated.rationale?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plainFallback = defaultRationale(sections: sections, itemOrder: itemOrder)
        let rationale = modelRationale.isEmpty
            ? plainFallback
            : accessibleRationale(modelRationale, fallback: plainFallback)
        return (
            OrganizationRecipe(sections: sections, itemOrder: itemOrder),
            rationale
        )
    }

    /// Model prose is untrusted display text. This pass removes punctuation
    /// and stock wording that Rank & Folder does not use in its interface.
    static func accessibleRationale(_ text: String, fallback: String) -> String {
        var result = text
            .replacingOccurrences(of: "\u{2014}", with: ", ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
        let replacements: [(String, String)] = [
            (#"\bensures\b"#, "keeps"),
            (#"\bensuring\b"#, "keeping"),
            (#"\bensured\b"#, "kept"),
            (#"\bensure\b"#, "help"),
            (#"\bnuanced\b"#, "detailed"),
            (#"\brobust\b"#, "reliable"),
            (#"\bseamless\b"#, "smooth"),
            (#"\bleverages\b"#, "uses"),
            (#"\bleveraging\b"#, "using"),
            (#"\bleverage\b"#, "use"),
            (#"\butilizes\b"#, "uses"),
            (#"\butilizing\b"#, "using"),
            (#"\butilize\b"#, "use"),
            (#"\bstreamlines\b"#, "simplifies"),
            (#"\bstreamlining\b"#, "simplifying"),
            (#"\bstreamline\b"#, "simplify"),
            (#"\bcomprehensive\b"#, "complete"),
            (#"\bcrucial\b"#, "important"),
            (#"\bfurthermore\b"#, "also"),
            (#"\bmoreover\b"#, "also"),
            (#"\bdelve\b"#, "look")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !containsDisallowedWriting(trimmed) else { return fallback }
        return String(trimmed.prefix(maximumRationaleCharacters))
    }

    private static func containsDisallowedWriting(_ text: String) -> Bool {
        let wordPattern = #"\b(?:action(?:able|ability)|aim(?:s|ed|ing)?|align(?:s|ed|ing|ment|ments)?|bolster(?:s|ed|ing)?|commendabl[ey]|delve(?:s|d)?|delving|drawn|enabl(?:e|es|ed|ing|ement)|encompass(?:es|ed|ing)?|enhanc(?:e|es|ed|ing|ement|ements)|ensur(?:e|es|ed|ing)|equip(?:s|ped|ping|ment)?|esteem(?:ed)?|facilitat(?:e|es|ed|ing|ion|or|ors)|foster(?:s|ed|ing)?|friendl(?:y|ier|iest|iness)|functionalit(?:y|ies)|grasp(?:s|ed|ing)?|guarantee(?:s|d|ing)?|hone(?:s|d)?|honing|influenc(?:e|es|ed|ing|ial)|instrumental(?:ly)?|intersection(?:s|al)?|intricat(?:e|ely|ies|y)|invaluabl[ey]|journey(?:s|ed|ing)?|landscape(?:s)?|leverag(?:e|es|ed|ing)|maximiz(?:e|es|ed|ing|ation)|meticulous(?:ly|ness)?|multifaceted|nuanc(?:e|es|ed|ing)|passionate(?:ly)?|passion|perspective(?:s)?|pivotal(?:ly)?|plethora|realm(?:s)?|rigor(?:ous|ously)?|robust(?:ly|ness)?|sacrific(?:e|es|ed|ing|ial)|seamless(?:ly)?|showcas(?:e|es|ed|ing)|strengthen(?:s|ed|ing)?|striv(?:e|es|ing)|strove|striven|synerg(?:y|ies|istic)|technique(?:s)?|transformative|translat(?:e|es|ed|ing|ion|ions)|tweak(?:s|ed|ing)?|utiliz(?:e|es|ed|ing|ation)|vital(?:ly)?|wish ?list(?:s)?)\b"#
        let contractionPattern = #"\b[A-Za-z]+['\u{2019}](?:t|re|ve|ll|d|m)\b"#
        return text.range(
            of: wordPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil || text.range(
            of: contractionPattern,
            options: .regularExpression
        ) != nil
    }

    /// Keeps only levels naming a criterion Rank & Folder supports, drops repeats
    /// of a criterion already used in the same area, and stops at the cap.
    /// Unknown values are skipped rather than rejecting the whole response, so
    /// one bad entry does not discard an otherwise usable layout.
    private static func validate(
        _ levels: [GeneratedRecipe.Level],
        maximum: Int
    ) -> [OrganizationLevel] {
        var seen: Set<AdvancedCriterion> = []
        var result: [OrganizationLevel] = []
        for level in levels {
            guard result.count < maximum else { break }
            guard let criterion = normalizedCriterion(level.criterion),
                  !seen.contains(criterion) else {
                continue
            }
            seen.insert(criterion)
            let direction = level.direction.flatMap(normalizedDirection)
            result.append(
                OrganizationLevel(
                    criterion: criterion,
                    direction: direction ?? .ascending
                )
            )
        }
        return result
    }

    private static func normalizedCriterion(_ rawValue: String) -> AdvancedCriterion? {
        let value = rawValue.lowercased().filter(\.isLetter)
        return switch value {
        case "name", "filename": .name
        case "kind", "type", "filetype": .kind
        case "fileextension", "extension", "suffix": .fileExtension
        case "datemodified", "modified", "lastmodified", "modificationdate": .dateModified
        case "datecreated", "created", "creationdate": .dateCreated
        case "size", "filesize": .size
        case "tags", "tag": .tags
        default: nil
        }
    }

    private static func normalizedDirection(_ rawValue: String) -> AdvancedSortDirection? {
        let value = rawValue.lowercased().filter(\.isLetter)
        return switch value {
        case "ascending", "asc", "atoz", "oldestfirst", "smallestfirst": .ascending
        case "descending", "desc", "ztoa", "newestfirst", "largestfirst": .descending
        default: nil
        }
    }

    private static func defaultRationale(
        sections: [OrganizationLevel],
        itemOrder: [OrganizationLevel]
    ) -> String {
        let sectionText = sections.isEmpty
            ? "Keep the folder in one list"
            : "Create sections by \(sections.map { $0.criterion.displayName.lowercased() }.joined(separator: ", then "))"
        let orderText = itemOrder.map { $0.criterion.displayName.lowercased() }.joined(separator: ", then ")
        return String("\(sectionText), and order items by \(orderText).".prefix(maximumRationaleCharacters))
    }
}

enum OllamaLoopbackPolicy {
    static func isExactLoopbackURL(_ url: URL) -> Bool {
        url.scheme == "http"
            && url.host == "127.0.0.1"
            && url.port == 11_434
    }

    /// URLSession asks its delegate for the request it should use after a
    /// redirect. Returning nil refuses the redirect before another endpoint
    /// can receive any Rank & Folder request data.
    static func requestAfterRedirect(_ proposedRequest: URLRequest) -> URLRequest? {
        nil
    }
}

struct OllamaPullEvent: Equatable, Sendable {
    let fraction: Double?
    let status: String
    let isSuccess: Bool
}

/// Incrementally parses Ollama's newline-delimited pull response without ever
/// allowing an unbounded line or response body to be buffered.
struct OllamaPullStreamParser {
    private struct WireEvent: Decodable {
        let status: String
        let total: Int64?
        let completed: Int64?
    }

    let maximumEvents: Int
    let maximumBytes: Int
    let maximumLineBytes: Int

    private var eventCount = 0
    private var byteCount = 0
    private var line = Data()
    private(set) var receivedSuccess = false

    init(
        maximumEvents: Int = 20_000,
        maximumBytes: Int = 16_777_216,
        maximumLineBytes: Int = 8_192
    ) {
        self.maximumEvents = maximumEvents
        self.maximumBytes = maximumBytes
        self.maximumLineBytes = maximumLineBytes
    }

    mutating func append(_ byte: UInt8) throws -> OllamaPullEvent? {
        byteCount += 1
        guard byteCount <= maximumBytes else {
            throw SuggestionValidationError.invalidResponse
        }
        if byte == 0x0A {
            if line.last == 0x0D { line.removeLast() }
            defer { line.removeAll(keepingCapacity: true) }
            return try decodeCurrentLine()
        }
        guard line.count < maximumLineBytes else {
            throw SuggestionValidationError.invalidResponse
        }
        line.append(byte)
        return nil
    }

    mutating func finish() throws -> OllamaPullEvent? {
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: false) }
        return try decodeCurrentLine()
    }

    func requireSuccessfulCompletion() throws {
        guard receivedSuccess else {
            throw SuggestionValidationError.unavailable(
                "Ollama ended the download before confirming it was complete."
            )
        }
    }

    private mutating func decodeCurrentLine() throws -> OllamaPullEvent? {
        guard !line.isEmpty else { return nil }
        eventCount += 1
        guard eventCount <= maximumEvents else {
            throw SuggestionValidationError.invalidResponse
        }
        guard let wire = try? JSONDecoder().decode(WireEvent.self, from: line) else {
            return nil
        }

        let fraction: Double?
        if let total = wire.total, let completed = wire.completed, total > 0 {
            fraction = max(0, min(1, Double(completed) / Double(total)))
        } else {
            fraction = nil
        }
        let success = wire.status == "success"
        if success { receivedSuccess = true }
        return OllamaPullEvent(
            fraction: fraction,
            status: wire.status,
            isSuccess: success
        )
    }
}
