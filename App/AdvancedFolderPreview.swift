import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The full preview window. It shows every saved level of a layout, including
/// the levels Finder cannot reproduce.
struct AdvancedFolderPreview: View {
    let resolution: ResolvedFolderLayout

    @Environment(\.dismiss) private var dismiss
    @State private var items: [AdvancedFolderItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var targetName: String {
        let name = resolution.targetFolderURL.lastPathComponent
        return name.isEmpty ? resolution.targetFolderURL.path : name
    }

    private var reloadID: String {
        "\(resolution.targetFolderURL.path)|\(resolution.sourceRevision.profileID.uuidString)|\(resolution.sourceRevision.updatedAt.timeIntervalSinceReferenceDate)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 540, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: reloadID) {
            await reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(RankFolderPalette.accent.opacity(0.13))
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(RankFolderPalette.accent)
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(targetName)
                        .rankFolderFont(.title2, weight: .semibold)
                    Text(headerSubtitle)
                        .rankFolderFont(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)

                Button {
                    NSWorkspace.shared.open(resolution.targetFolderURL)
                } label: {
                    Label("Open in Finder", systemImage: "arrow.up.forward.app")
                }

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(resolution.sourceProfile.advancedRules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .rankFolderFont(.caption2, weight: .bold)
                                .foregroundStyle(.secondary)
                            Image(systemName: rule.criterion.systemImage)
                            Text(rule.criterion.displayName)
                                .fontWeight(.medium)
                        }
                        .rankFolderFont(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())

                        if index < resolution.sourceProfile.advancedRules.count - 1 {
                            Image(systemName: "chevron.right")
                                .rankFolderFont(.caption2, weight: .bold)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Active organization plan")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var headerSubtitle: String {
        switch resolution.origin {
        case .exact:
            "Folder preview · Read only"
        case .inherited:
            "Using layout from \(resolution.sourceProfile.displayName) · Read only"
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading folder names and metadata…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Could not open folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try again") { Task { await reload() } }
            }
        } else {
            FinderColumnPreview(
                folderName: targetName,
                items: items,
                rules: resolution.sourceProfile.advancedRules,
                isLoading: false,
                errorMessage: nil
            )
            .padding(18)
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadingTask = Task.detached(priority: .userInitiated) {
                try AdvancedFolderLoader.load(resolution: resolution)
            }
            items = try await withTaskCancellationHandler {
                try await loadingTask.value
            } onCancel: {
                loadingTask.cancel()
            }
        } catch is CancellationError {
            return
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Draws a folder as grouped and sorted rows in a list, the way Finder would
/// show it if Finder could show every level.
struct FinderColumnPreview: View {
    let folderName: String
    let items: [AdvancedFolderItem]
    let rules: [AdvancedViewRule]
    let isLoading: Bool
    let errorMessage: String?

    /// Grouping and sorting the whole folder is proportional to its item count,
    /// so it is built once per items-and-rules change rather than on every body
    /// evaluation. A large folder would otherwise regroup on each redraw.
    @State private var lines: [FinderColumnPreviewLine] = []

    private var rebuildID: String {
        let ruleSignature = rules
            .map { "\($0.behavior.rawValue):\($0.criterion.rawValue):\($0.direction.rawValue)" }
            .joined(separator: "|")
        return "\(items.count)|\(items.first?.url.path ?? "")|\(ruleSignature)"
    }

    private func rebuildLines() {
        lines = flatten(
            AdvancedHierarchyBuilder.build(items: items, rules: rules),
            depth: 0
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                parentColumn
                Divider()
                contentsColumn
            }
            Divider()
            HStack {
                Text("\(items.count) \(items.count == 1 ? "item" : "items")")
                Spacer()
                Label("Read only", systemImage: "lock")
            }
            .rankFolderFont(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(.bar)
        }
        .frame(minHeight: 330)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .onAppear(perform: rebuildLines)
        .onChange(of: rebuildID) { _, _ in rebuildLines() }
    }

    private var parentColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder")
                .rankFolderFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(RankFolderPalette.action)
                Text(folderName)
                    .rankFolderFont(.callout, weight: .medium)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RankFolderPalette.action.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .padding(.horizontal, 6)
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 184, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.88))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected folder, \(folderName)")
    }

    @ViewBuilder
    private var contentsColumn: some View {
        if isLoading {
            ProgressView("Preparing preview…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "lock.trianglebadge.exclamationmark")
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if lines.isEmpty {
            ContentUnavailableView("This folder is empty", systemImage: "folder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        previewLine(line)
                    }
                }
                .padding(.vertical, 8)
            }
            .accessibilityLabel("Preview of every visible item grouped by the current layout")
        }
    }

    @ViewBuilder
    private func previewLine(_ line: FinderColumnPreviewLine) -> some View {
        switch line.content {
        case .group(let title):
            HStack(spacing: 10) {
                Color.clear.frame(width: CGFloat(line.depth) * 18)
                Text(title)
                    .rankFolderFont(.callout, weight: .semibold)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.primary.opacity(0.13))
                    .frame(height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, line.depth == 0 ? 13 : 8)
            .padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)

        case .item(let item):
            HStack(spacing: 9) {
                Color.clear.frame(width: CGFloat(line.depth) * 18 + 2)
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(item.name)
                    .rankFolderFont(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .accessibilityLabel("\(item.name), \(item.finderKindGroup)")
        }
    }

    private func flatten(
        _ nodes: [AdvancedDisplayNode],
        depth: Int
    ) -> [FinderColumnPreviewLine] {
        var result: [FinderColumnPreviewLine] = []
        for node in nodes {
            switch node.content {
            case .group(let title, _):
                result.append(.init(
                    id: node.id,
                    depth: depth,
                    content: .group(title)
                ))
                if let children = node.children {
                    result.append(contentsOf: flatten(children, depth: min(depth + 1, 6)))
                }
            case .item(let item):
                result.append(.init(
                    id: node.id,
                    depth: depth,
                    content: .item(item)
                ))
            }
        }
        return result
    }
}

/// One rendered row, which is either a group heading or an item.
private struct FinderColumnPreviewLine: Identifiable {
    enum Content {
        case group(String)
        case item(AdvancedFolderItem)
    }

    let id: String
    let depth: Int
    let content: Content
}

/// The metadata read for one item in a folder. These are the same attributes
/// Finder already shows in a list view. File contents are never read.
struct AdvancedFolderItem: Identifiable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let kind: String
    let fileExtension: String
    let dateModified: Date?
    let dateCreated: Date?
    let size: Int64?
    let tags: [String]
    let contentTypeIdentifier: String?

    var id: URL { url }

    var finderKindGroup: String {
        if isDirectory { return "Folders" }
        let loweredExtension = fileExtension.lowercased()
        if loweredExtension == "pdf" { return "PDF Documents" }
        if let contentTypeIdentifier,
           let type = UTType(contentTypeIdentifier) {
            if type.conforms(to: .image) { return "Images" }
            if type.conforms(to: .audio) { return "Music" }
            if type.conforms(to: .movie) { return "Movies" }
            if type.conforms(to: .application) { return "Applications" }
            if type.conforms(to: .text) { return "Documents" }
        }
        if ["txt", "rtf", "md", "tex", "aux", "bib", "doc", "docx", "pages"]
            .contains(loweredExtension) {
            return "Documents"
        }
        return "Other"
    }
}

/// Reads the items of a folder after confirming the folder is still the one that
/// was verified, so a folder swapped underneath the app is not read by mistake.
enum AdvancedFolderLoader {
    static func load(resolution: ResolvedFolderLayout) throws -> [AdvancedFolderItem] {
        guard resolution.targetIdentity.matchesLiveFolderURL(
            resolution.targetFolderURL
        ) else {
            throw SuggestionValidationError.unavailable(
                "This folder changed after Rank & Folder verified it. Close this view and open it again before Rank & Folder reads its metadata."
            )
        }
        let folderURL = resolution.targetFolderURL
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentTypeKey,
            .tagNamesKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var items: [AdvancedFolderItem] = []
        items.reserveCapacity(urls.count)
        for url in urls {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = (values?.isDirectory ?? url.hasDirectoryPath)
                && values?.isPackage != true
            items.append(AdvancedFolderItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                kind: isDirectory
                    ? "Folder"
                    : values?.contentType?.localizedDescription ?? "File",
                fileExtension: url.pathExtension.isEmpty ? "No extension" : url.pathExtension,
                dateModified: values?.contentModificationDate,
                dateCreated: values?.creationDate,
                size: values?.fileSize.map(Int64.init),
                tags: values?.tagNames ?? [],
                contentTypeIdentifier: values?.contentType?.identifier
            ))
        }
        return items
    }
}

/// One node of the grouped tree, either a heading with a count or a single item.
struct AdvancedDisplayNode: Identifiable {
    enum Content {
        case group(title: String, count: Int)
        case item(AdvancedFolderItem)
    }

    let id: String
    let content: Content
    let children: [AdvancedDisplayNode]?
}

/// Turns a flat list of items and a list of rules into the nested tree the
/// preview draws.
enum AdvancedHierarchyBuilder {
    private struct BucketKey: Hashable {
        let label: String
        let rank: Double?
    }

    static func build(
        items: [AdvancedFolderItem],
        rules: [AdvancedViewRule]
    ) -> [AdvancedDisplayNode] {
        let groupRules = rules.filter { $0.behavior == .group }
        let sortRules = rules.filter { $0.behavior == .sort }
        return buildLevel(
            items: items,
            groupRules: groupRules,
            sortRules: sortRules,
            depth: 0,
            path: "root"
        )
    }

    private static func buildLevel(
        items: [AdvancedFolderItem],
        groupRules: [AdvancedViewRule],
        sortRules: [AdvancedViewRule],
        depth: Int,
        path: String
    ) -> [AdvancedDisplayNode] {
        guard depth < groupRules.count else {
            return sorted(items, by: sortRules).map {
                AdvancedDisplayNode(
                    id: "item:\($0.url.path)",
                    content: .item($0),
                    children: nil
                )
            }
        }

        let rule = groupRules[depth]
        let buckets = Dictionary(grouping: items) {
            bucket(for: $0, criterion: rule.criterion)
        }
        let orderedKeys = buckets.keys.sorted {
            compareBuckets($0, $1, direction: rule.direction)
        }

        return orderedKeys.map { key in
            let bucketItems = buckets[key] ?? []
            let nodePath = "\(path)/\(depth):\(key.label)"
            return AdvancedDisplayNode(
                id: nodePath,
                content: .group(title: key.label, count: bucketItems.count),
                children: buildLevel(
                    items: bucketItems,
                    groupRules: groupRules,
                    sortRules: sortRules,
                    depth: depth + 1,
                    path: nodePath
                )
            )
        }
    }

    private static func sorted(
        _ items: [AdvancedFolderItem],
        by rules: [AdvancedViewRule]
    ) -> [AdvancedFolderItem] {
        items.sorted { left, right in
            for rule in rules {
                let result = compare(left, right, criterion: rule.criterion)
                guard result != .orderedSame else { continue }
                return rule.direction == .ascending
                    ? result == .orderedAscending
                    : result == .orderedDescending
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func compare(
        _ left: AdvancedFolderItem,
        _ right: AdvancedFolderItem,
        criterion: AdvancedCriterion
    ) -> ComparisonResult {
        switch criterion {
        case .name:
            left.name.localizedStandardCompare(right.name)
        case .kind:
            left.finderKindGroup.localizedStandardCompare(right.finderKindGroup)
        case .fileExtension:
            left.fileExtension.localizedStandardCompare(right.fileExtension)
        case .dateModified:
            compareOptional(left.dateModified, right.dateModified)
        case .dateCreated:
            compareOptional(left.dateCreated, right.dateCreated)
        case .size:
            compareOptional(left.size, right.size)
        case .tags:
            left.tags.joined(separator: ",").localizedStandardCompare(
                right.tags.joined(separator: ",")
            )
        }
    }

    private static func compareOptional<T: Comparable>(_ left: T?, _ right: T?) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?):
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }

    private static func bucket(
        for item: AdvancedFolderItem,
        criterion: AdvancedCriterion
    ) -> BucketKey {
        switch criterion {
        case .name:
            let initial = item.name.first.map { String($0).uppercased() } ?? "#"
            return BucketKey(label: initial, rank: nil)
        case .kind:
            let rank: Double?
            switch item.finderKindGroup {
            case "Folders": rank = 0
            case "Documents": rank = 1
            case "PDF Documents": rank = 2
            case "Images": rank = 3
            case "Music": rank = 4
            case "Movies": rank = 5
            case "Applications": rank = 6
            default: rank = 7
            }
            return BucketKey(label: item.finderKindGroup, rank: rank)
        case .fileExtension:
            return BucketKey(label: item.fileExtension.uppercased(), rank: nil)
        case .dateModified:
            return dateBucket(item.dateModified)
        case .dateCreated:
            return dateBucket(item.dateCreated)
        case .size:
            guard !item.isDirectory, let size = item.size else {
                return BucketKey(label: item.isDirectory ? "Folders" : "Unknown size", rank: -1)
            }
            switch size {
            case ..<100_000:
                return BucketKey(label: "Small: under 100 KB", rank: 0)
            case ..<10_000_000:
                return BucketKey(label: "Medium: 100 KB to 10 MB", rank: 1)
            case ..<1_000_000_000:
                return BucketKey(label: "Large: 10 MB to 1 GB", rank: 2)
            default:
                return BucketKey(label: "Very Large: over 1 GB", rank: 3)
            }
        case .tags:
            return BucketKey(
                label: item.tags.isEmpty ? "No tags" : item.tags.joined(separator: ", "),
                rank: nil
            )
        }
    }

    private static func dateBucket(_ date: Date?) -> BucketKey {
        guard let date else { return BucketKey(label: "No date", rank: -1) }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let label: String
        if calendar.isDateInToday(date) {
            label = "Today"
        } else if calendar.isDateInYesterday(date) {
            label = "Yesterday"
        } else {
            label = DateFormatter.localizedString(from: day, dateStyle: .medium, timeStyle: .none)
        }
        return BucketKey(label: label, rank: day.timeIntervalSince1970)
    }

    private static func compareBuckets(
        _ left: BucketKey,
        _ right: BucketKey,
        direction: AdvancedSortDirection
    ) -> Bool {
        let result: ComparisonResult
        if let leftRank = left.rank, let rightRank = right.rank, leftRank != rightRank {
            result = leftRank < rightRank ? .orderedAscending : .orderedDescending
        } else {
            result = left.label.localizedStandardCompare(right.label)
        }
        guard result != .orderedSame else { return false }
        return direction == .ascending
            ? result == .orderedAscending
            : result == .orderedDescending
    }
}
