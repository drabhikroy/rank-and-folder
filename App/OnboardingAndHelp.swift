import AppKit
import SwiftUI

enum SuggestionMethod: String, CaseIterable, Identifiable {
    case ollama
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: "Use a local model"
        case .off: "Choose layouts myself"
        }
    }

    var detail: String {
        switch self {
        case .ollama:
            "More model choices, kept on this Mac. Rank & Folder can manage setup; Terminal is optional."
        case .off:
            "No model or download. Choose every section and order rule yourself."
        }
    }

    var systemImage: String {
        switch self {
        case .ollama: "desktopcomputer"
        case .off: "hand.tap"
        }
    }
}

enum OllamaSetupStyle: String, CaseIterable, Identifiable {
    case rankFolder
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rankFolder: "Keep it in Rank & Folder"
        case .terminal: "Use my existing Ollama"
        }
    }
}

@MainActor
final class OnboardingStore: ObservableObject {
    static let currentVersion = 5

    private enum Key {
        static let completedVersion = "onboarding.completedVersion"
        static let suggestionMethod = "suggestions.method"
        static let allowsCompatibilityCheck = "suggestions.allowsCompatibilityCheck"
        static let ollamaSetupStyle = "suggestions.ollamaSetupStyle"
    }

    @Published var suggestionMethod: SuggestionMethod {
        didSet { defaults.set(suggestionMethod.rawValue, forKey: Key.suggestionMethod) }
    }

    @Published var allowsCompatibilityCheck: Bool {
        didSet { defaults.set(allowsCompatibilityCheck, forKey: Key.allowsCompatibilityCheck) }
    }

    @Published var ollamaSetupStyle: OllamaSetupStyle {
        didSet { defaults.set(ollamaSetupStyle.rawValue, forKey: Key.ollamaSetupStyle) }
    }

    /// Only completion state is saved. Opening the tour always starts on its first page.
    @Published var isWalkthroughPresented = false
    @Published private(set) var walkthroughResetToken = UUID()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedValue = defaults.string(forKey: Key.suggestionMethod)
        let currentMethod: SuggestionMethod = savedValue == SuggestionMethod.off.rawValue
            ? .off
            : savedValue == nil ? .off : .ollama
        suggestionMethod = currentMethod
        defaults.set(currentMethod.rawValue, forKey: Key.suggestionMethod)
        allowsCompatibilityCheck = defaults.bool(forKey: Key.allowsCompatibilityCheck)
        ollamaSetupStyle = OllamaSetupStyle(
            rawValue: defaults.string(forKey: Key.ollamaSetupStyle) ?? ""
        ) ?? .rankFolder
    }

    func shouldShowAutomatically(hasExistingProfiles: Bool) -> Bool {
        defaults.integer(forKey: Key.completedVersion) < Self.currentVersion
            && !hasExistingProfiles
    }

    func completeTour() {
        defaults.set(Self.currentVersion, forKey: Key.completedVersion)
    }

    func presentWalkthrough() {
        walkthroughResetToken = UUID()
        isWalkthroughPresented = true
    }

    func dismissWalkthrough() {
        isWalkthroughPresented = false
    }

    func forgetCompatibilityPermission() {
        allowsCompatibilityCheck = false
    }

    func resetToDefaultsAndShowTour() {
        suggestionMethod = .off
        allowsCompatibilityCheck = false
        ollamaSetupStyle = .rankFolder
        defaults.removeObject(forKey: Key.completedVersion)
        defaults.removeObject(forKey: "suggestions.ollamaModel")
        defaults.synchronize()
        ModelCenterViewModel.shared.selectedModelID = LocalModelDescriptor.defaultModelID
        ModelCenterViewModel.shared.stopMonitoring()
        walkthroughResetToken = UUID()
        isWalkthroughPresented = true
    }
}

struct WalkthroughView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rankFolderPanelSpacing) private var panelSpacing
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var store: ProfileStore
    let selectProfile: (UUID) -> Void
    @State private var pageIndex = 0
    @State private var isChoosingFirstFolder = false
    @AccessibilityFocusState private var pageTitleIsFocused: Bool

    private var pages: [TourPage] {
        var result: [TourPage] = [.welcome, .language, .subfolders, .suggestions]
        if onboarding.suggestionMethod == .off {
            result.append(.privacy)
        } else {
            result.append(.suggestionSetup)
        }
        return result
    }

    private var currentPage: TourPage {
        pages[min(pageIndex, pages.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Label("Quick tour", systemImage: "sparkles")
                        .rankFolderFont(.title3, weight: .semibold, design: .rounded)
                    Spacer()
                    Text("Step \(pageIndex + 1) of \(pages.count)")
                        .rankFolderFont(.callout, weight: .medium, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(pageIndex + 1), total: Double(pages.count))
                    .progressViewStyle(.linear)
            }
            .padding(.horizontal, 28 * panelSpacing)
            .padding(.vertical, 16 * panelSpacing)
            .background(.regularMaterial)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(pageIndex + 1) of \(pages.count)")

            Group {
                switch currentPage {
                case .welcome: welcomePage
                case .language: languagePage
                case .subfolders: subfoldersPage
                case .suggestions: suggestionChoicePage
                case .suggestionSetup: suggestionSetupPage
                case .privacy: privacyPage
                }
            }
            .id(currentPage)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: currentPage)

            Divider()

            HStack(spacing: 10) {
                Button("Skip for now") {
                    onboarding.completeTour()
                    onboarding.dismissWalkthrough()
                    dismissWindow(id: "tour")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                .focusable(false)

                Spacer()

                Button("Back") {
                    pageIndex = max(0, pageIndex - 1)
                }
                .buttonStyle(RankFolderSecondaryActionButtonStyle())
                .disabled(pageIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button(primaryActionTitle) {
                    performPrimaryAction()
                }
                .buttonStyle(RankFolderPrimaryActionButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                .focusable(false)
                .id(primaryActionTitle)
                .disabled(isChoosingFirstFolder)
            }
            .controlSize(.large)
            .padding(20 * panelSpacing)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .frame(minWidth: 520, idealWidth: 820, minHeight: 400, idealHeight: 690)
        .background(RankFolderBackdrop())
        .textSelection(.enabled)
        .onAppear {
            pageIndex = 0
            isChoosingFirstFolder = false
            pageTitleIsFocused = true
        }
        .onDisappear {
            pageIndex = 0
            isChoosingFirstFolder = false
        }
        .onChange(of: currentPage) { _, _ in
            pageTitleIsFocused = false
            Task { @MainActor in
                await Task.yield()
                pageTitleIsFocused = true
            }
        }
        .onChange(of: onboarding.suggestionMethod) { _, _ in
            pageIndex = min(pageIndex, pages.count - 1)
        }
        .onChange(of: onboarding.walkthroughResetToken) { _, _ in
            pageIndex = 0
            isChoosingFirstFolder = false
        }
    }

    private var primaryActionTitle: String {
        if currentPage == .suggestionSetup, onboarding.suggestionMethod == .ollama {
            return "Choose a model"
        }
        guard currentPage == .privacy else { return "Continue" }
        return store.profiles.isEmpty ? "Choose first folder" : "Open Rank & Folder"
    }

    private func performPrimaryAction() {
        if currentPage == .suggestionSetup, onboarding.suggestionMethod == .ollama {
            onboarding.completeTour()
            onboarding.dismissWalkthrough()
            dismissWindow(id: "tour")
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "models")
            return
        }
        guard currentPage == .privacy else {
            pageIndex += 1
            return
        }

        if store.profiles.isEmpty {
            guard !isChoosingFirstFolder else { return }
            isChoosingFirstFolder = true
            Task { @MainActor in
                defer { isChoosingFirstFolder = false }
                guard let profileID = await FolderProfileCreationCoordinator.chooseAndAdd(to: store) else {
                    return
                }
                selectProfile(profileID)
                finishTour()
            }
            return
        }

        finishTour()
    }

    private func finishTour() {
        onboarding.completeTour()
        onboarding.dismissWalkthrough()
        dismissWindow(id: "tour")
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "profiles")
    }

    private var welcomePage: some View {
        TourCard(
            icon: "folder.badge.gearshape",
            title: "Organize each folder in the way that fits it",
            subtitle: "Rank & Folder remembers a separate layout for every folder. It does not move, rename, or change your files.",
            titleFocus: $pageTitleIsFocused
        ) {
            AdaptiveTourFeatures(features: [
                TourFeatureContent(
                    icon: "plus",
                    title: "Add a folder",
                    detail: "Choose one with the + button."
                ),
                TourFeatureContent(
                    icon: "rectangle.3.group",
                    title: "Build a layout",
                    detail: "Add as many useful levels as you need."
                ),
                TourFeatureContent(
                    icon: "eye",
                    title: "Review it",
                    detail: "Nothing changes until you open or apply it."
                )
            ])
        }
    }

    private var subfoldersPage: some View {
        TourCard(
            icon: "folder.badge.plus",
            title: "One layout can cover related folders",
            subtitle: "Choose whether a saved layout stays in one folder or is also used in folders inside it.",
            titleFocus: $pageTitleIsFocused
        ) {
            VStack(spacing: 16) {
                AdaptiveTourFeatures(features: [
                    TourFeatureContent(
                        icon: "folder",
                        title: "This folder only",
                        detail: "Keep its saved layout in this folder."
                    ),
                    TourFeatureContent(
                        icon: "folder.badge.plus",
                        title: "Include subfolders",
                        detail: "Use the same layout in folders inside it."
                    ),
                    TourFeatureContent(
                        icon: "arrow.triangle.branch",
                        title: "Make exceptions",
                        detail: "Give a subfolder its own layout, or leave that branch alone."
                    )
                ])

                Label(
                    "The closest saved choice wins. Rank & Folder does not scan subfolders just because Include subfolders is on.",
                    systemImage: "hand.raised"
                )
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var languagePage: some View {
        TourCard(
            icon: "rectangle.split.3x1",
            title: "Sections and item order",
            subtitle: "They use the same file information, but they do different jobs.",
            titleFocus: $pageTitleIsFocused
        ) {
            VStack(spacing: 14) {
                ExplanationPanel(
                    number: 1,
                    icon: "rectangle.split.3x1",
                    title: "Sections create visible headings",
                    detail: "Sections by File type can create headings such as Images, PDFs, and Folders. Add another level to make smaller sections inside each one."
                )
                Image(systemName: "arrow.down")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                ExplanationPanel(
                    number: 2,
                    icon: "arrow.up.arrow.down",
                    title: "Item order decides what comes first",
                    detail: "Inside the smallest section, show files by Name, Last modified, Size, or another useful fact. Extra rules break ties."
                )
                Text("Finder calls these “Group By” and “Sort By.” Rank & Folder uses the plainer terms throughout the app.")
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionChoicePage: some View {
        TourCard(
            icon: "cpu",
            title: "Would you like to use a local model?",
            subtitle: "A model can compare several folder patterns before proposing a layout. Rank & Folder works without one.",
            titleFocus: $pageTitleIsFocused
        ) {
            Grid(horizontalSpacing: 14) {
                GridRow(alignment: .top) {
                    ForEach([SuggestionMethod.off, .ollama]) { method in
                        TourChoiceRow(
                            method: method,
                            isSelected: onboarding.suggestionMethod == method
                        ) {
                            onboarding.suggestionMethod = method
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var suggestionSetupPage: some View {
        switch onboarding.suggestionMethod {
        case .ollama:
            TourCard(
                icon: "shippingbox",
                title: "Choose a model in three short steps",
                subtitle: "Choose where Ollama runs, connect it, then select a model. The next button opens Models directly.",
                titleFocus: $pageTitleIsFocused
            ) {
                VStack(spacing: 14) {
                    ExplanationPanel(
                        number: 1,
                        icon: "shippingbox",
                        title: "Choose where Ollama runs",
                        detail: "Use an existing Ollama service, or let Rank & Folder keep a verified copy in its own support folder."
                    )
                    ExplanationPanel(
                        number: 2,
                        icon: "arrow.triangle.2.circlepath",
                        title: "Connect to Ollama",
                        detail: "Rank & Folder checks the local service and detects changes while Models is open."
                    )
                    ExplanationPanel(
                        number: 3,
                        icon: "cpu",
                        title: "Choose a model",
                        detail: "Compare model cards by purpose, memory, download size, and limits. You choose what to add."
                    )
                    PrivacyLine(
                        icon: "hand.raised.fill",
                        text: "The model receives counts and date or size ranges, not file contents or filenames."
                    )
                    PrivacyLine(
                        icon: "square.stack.3d.up",
                        text: "If you ask for another idea, Rank & Folder keeps every different suggestion in the model window."
                    )
                }
            }

        case .off:
            EmptyView()
        }
    }

    private var privacyPage: some View {
        TourCard(
            icon: "checkmark.circle.fill",
            title: "You are ready",
            subtitle: "Add a folder, choose its sections and item order, then review the result. You can reopen this tour from Help at any time.",
            titleFocus: $pageTitleIsFocused
        ) {
            VStack(alignment: .leading, spacing: 16) {
                PrivacyLine(icon: "doc", text: "Rank & Folder does not move, rename, or delete files, and it never reads file contents.")
                PrivacyLine(icon: "folder.badge.questionmark", text: "Folder access is granted one folder at a time. Full Disk Access is not required.")
                PrivacyLine(icon: "accessibility", text: "Finder automation and its Accessibility permission are optional.")
                PrivacyLine(icon: "cpu", text: "Models are optional and receive a limited folder summary only when you ask.")
            }
        }
    }
}

private enum TourPage: Hashable {
    case welcome
    case language
    case subfolders
    case suggestions
    case suggestionSetup
    case privacy
}

private struct TourCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let titleFocus: AccessibilityFocusState<Bool>.Binding
    let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        titleFocus: AccessibilityFocusState<Bool>.Binding,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.titleFocus = titleFocus
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    RankFolderPalette.action.opacity(0.25),
                                    RankFolderPalette.coral.opacity(0.15),
                                    RankFolderPalette.plum.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(RankFolderPalette.action)
                }
                .frame(width: 68, height: 68)
                .shadow(color: RankFolderPalette.plum.opacity(0.14), radius: 16, y: 7)
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused(titleFocus)
                    Text(subtitle)
                        .rankFolderFont(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
                    .frame(maxWidth: 650, alignment: .leading)
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TourFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RankFolderPalette.accent)
                .frame(width: 38, height: 38)
                .background(RankFolderPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).rankFolderFont(.headline, weight: .semibold)
                Text(detail)
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct TourFeatureContent: Identifiable {
    let icon: String
    let title: String
    let detail: String

    var id: String { title }
}

private struct AdaptiveTourFeatures: View {
    let features: [TourFeatureContent]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                featureCard(feature)
                if index < features.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
    }

    private func featureCard(_ feature: TourFeatureContent) -> some View {
        TourFeature(
            icon: feature.icon,
            title: feature.title,
            detail: feature.detail
        )
    }
}

private struct ExplanationPanel: View {
    let number: Int
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(RankFolderPalette.accent.opacity(0.12))
                Image(systemName: icon).foregroundStyle(RankFolderPalette.accent)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)").rankFolderFont(.headline, weight: .semibold)
                Text(detail).rankFolderFont(.body).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct TourChoiceRow: View {
    let method: SuggestionMethod
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        method == .ollama ? RankFolderPalette.coral : RankFolderPalette.action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: method.systemImage)
                        .rankFolderFont(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(
                            tint.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .rankFolderFont(.title3)
                        .foregroundStyle(isSelected ? tint : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(method.title)
                        .rankFolderFont(.title3, weight: .semibold)
                    Text(method.detail)
                        .rankFolderFont(.body)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .padding(18)
            .foregroundStyle(Color.primary)
            .background(
                isSelected
                    ? tint.opacity(0.13)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? tint.opacity(0.8) : Color.clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct PrivacyLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(RankFolderPalette.accent.opacity(0.10))
                Image(systemName: icon)
                    .foregroundStyle(RankFolderPalette.accent)
            }
            .frame(width: 44, height: 44)
            Text(text)
                .rankFolderFont(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct CompatibilityConsent: View {
    @ObservedObject var onboarding: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Optional: check which downloadable models fit this Mac")
                .rankFolderFont(.headline, weight: .semibold)
            Text("Rank & Folder can read the processor type, memory, macOS version, and free storage. The check stays on this Mac, and the raw details are not saved or shared.")
                .rankFolderFont(.callout)
                .foregroundStyle(.secondary)
            Toggle("Allow local compatibility checks", isOn: $onboarding.allowsCompatibilityCheck)
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Help Center

struct RankFolderHelpView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var onboarding: OnboardingStore
    @State private var selection: HelpTopic? = .quickStart
    @State private var searchText = ""

    private var filteredTopics: [HelpTopic] {
        guard !searchText.isEmpty else { return HelpTopic.allCases }
        return HelpTopic.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.searchTerms.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredTopics) { topic in
                    Label(topic.title, systemImage: topic.systemImage)
                        .tag(topic)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Rank & Folder help")
            .searchable(text: $searchText, prompt: "Search help")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if let selection {
                HelpTopicView(topic: selection)
                    .id(selection)
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onboarding.presentWalkthrough()
                    openWindow(id: "tour")
                } label: {
                    Label("Show welcome tour", systemImage: "rectangle.on.rectangle")
                }
            }
        }
        .frame(minWidth: 540, minHeight: 400)
        .onChange(of: filteredTopics) { _, topics in
            if let selection, !topics.contains(selection) {
                self.selection = topics.first
            }
        }
    }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case quickStart
    case sectionsAndOrder
    case layoutsInSubfolders
    case organizedView
    case models
    case appearance
    case privacy
    case accessibility
    case shortcuts
    case safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickStart: "Quick start"
        case .sectionsAndOrder: "Sections and item order"
        case .layoutsInSubfolders: "Layouts in subfolders"
        case .organizedView: "More than two levels"
        case .models: "Local models"
        case .appearance: "Appearance and color vision"
        case .privacy: "Privacy and permissions"
        case .accessibility: "Accessibility help"
        case .shortcuts: "Keyboard shortcuts"
        case .safety: "Safety and about"
        }
    }

    var systemImage: String {
        switch self {
        case .quickStart: "figure.walk"
        case .sectionsAndOrder: "rectangle.split.3x1"
        case .layoutsInSubfolders: "folder.badge.plus"
        case .organizedView: "rectangle.3.group"
        case .models: "cpu"
        case .appearance: "paintpalette"
        case .privacy: "hand.raised"
        case .accessibility: "accessibility"
        case .shortcuts: "command"
        case .safety: "lock.shield"
        }
    }

    var searchTerms: String {
        switch self {
        case .quickStart: "add folder apply open begin plus remove"
        case .sectionsAndOrder: "group by sort by headings sequence arrangement terminology"
        case .layoutsInSubfolders: "subfolder include share related inheritance exception closest parent child"
        case .organizedView: "multi level custom Finder limitation three levels"
        case .models: "model Ollama local download setup layout review metadata optional"
        case .appearance: "light dark system theme color colour blindness vision monochrome contrast"
        case .privacy: "data contents filenames Mac specs permission revoke local"
        case .accessibility: "System Settings permission not recognized apply error"
        case .shortcuts: "keys command new delete help"
        case .safety: "source available malicious network security source code license reset defaults start over"
        }
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(topic.title, systemImage: topic.systemImage)
                    .rankFolderFont(.largeTitle, weight: .semibold)
                topicContent
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(topic.title)
    }

    @ViewBuilder
    private var topicContent: some View {
        switch topic {
        case .quickStart:
            HelpIntro("Start from Home, then work through one small decision at a time.")
            HelpSteps(steps: [
                ("Start from Home", "Choose your first folder from Home, or click + in the sidebar whenever you want to add another."),
                ("Review optional folder settings", "Step 1 controls subfolders and optional Finder automation. The defaults are safe to keep."),
                ("Build the layout", "Step 2 contains Sections, Item Order, and Preview. Only the current part appears on screen."),
                ("Open the result", "Preview works in Rank & Folder without Accessibility. If optional Finder automation is on and the layout fits Finder, you can also use Open in Finder and Apply.")
            ])
            HelpCallout(icon: "lightbulb", text: "Folder settings stay collapsed until you need them. Accessibility is never required just to preview a layout.")
            HelpCallout(icon: "macwindow", text: "Quick Tour, Settings, folder previews, model comparisons, and model results are normal windows. Drag their title bars to move them and drag any edge or corner to resize them.")

        case .sectionsAndOrder:
            HelpIntro("Sections and item order are related, but they are not the same.")
            HelpDefinition(
                title: "Sections",
                example: "Sections by File type create headings such as Images, PDFs, and Folders.",
                icon: "rectangle.split.3x1"
            )
            HelpDefinition(
                title: "Item order",
                example: "Order by Last modified puts newer or older items first inside the smallest section.",
                icon: "arrow.up.arrow.down"
            )
            HelpCallout(icon: "character.book.closed", text: "Finder calls Sections “Group By” and item order “Sort By.” Rank & Folder uses plainer wording because the Finder terms are easy to confuse.")
            Text("A three-level example: first make sections by File type, then smaller sections by Last modified, then order each final section by Name.")

        case .layoutsInSubfolders:
            HelpIntro("Save one layout for a folder, then choose whether folders inside it should use the same layout.")
            HelpSteps(steps: [
                ("Choose where it applies", "Turn on Use this layout in subfolders when related folders should use the same organization."),
                ("Make exceptions when needed", "A subfolder can have its own layout. Its saved choice is used there instead."),
                ("Leave a branch alone", "Choose Leave a subfolder alone when Rank & Folder should not organize that folder or folders inside it."),
                ("See where a layout came from", "Rank & Folder names the saved folder supplying a layout, so you do not have to guess.")
            ])
            HelpCallout(
                icon: "hand.raised",
                text: "Turning on Use this layout in subfolders does not scan those folders, read their contents, or change any files. Rank & Folder chooses a layout only when you open or preview a folder."
            )
            HelpCallout(
                icon: "character.book.closed",
                text: "Some software calls this inheritance. Rank & Folder simply tells you which folder a layout comes from."
            )

        case .organizedView:
            HelpIntro("Finder supports one section choice and one order choice. Rank & Folder can show the complete hierarchy when your plan needs more.")
            HelpSteps(steps: [
                ("Build one plan", "Add all the section levels and order rules you want."),
                ("Rank & Folder checks it", "One section plus one standard order rule can be applied in Finder."),
                ("Preview every level", "Folder preview places every visible item into the complete grouping structure. Scroll through the whole folder before saving or applying anything.")
            ])
            HelpCallout(icon: "hand.raised", text: "Folder preview never moves, renames, deletes, or edits files. It uses real file icons and a Finder-like column layout, but it is not a screen recording or a pixel copy of Finder.")

        case .models:
            HelpIntro("Models are optional. Choosing the model path in the quick tour opens Models directly; you can also use Home or the CPU button later.")
            HelpSteps(steps: [
                ("Choose where Ollama runs", "Keep a verified private copy inside Rank & Folder, or connect to Ollama already running on this Mac."),
                ("Follow the matching path", "The private path offers reviewed in-app downloads. The existing-Ollama path detects both available and currently running models. Its model command uses ollama run, which starts an available model or downloads it first when needed."),
                ("Choose a model", "Once Ollama is ready, compare up to two cards per row by folder use, memory, download size, speed, license, benefits, and limits."),
                ("Review the result", "Rank & Folder counts visible file types, date ranges, size ranges, folders, and tags. It does not include filenames or file contents. You inspect the proposed layout before saving it."),
                ("Compare different ideas", "Try another asks for a different valid layout. Every different idea stays available in the same window until you close it."),
                ("Preview before saving", "The review first explains the proposed organization. Preview this layout places every visible item into that grouping structure. Save this layout is available only from that preview.")
            ])
            HelpCallout(icon: "star", text: "Qwen 3 · 4B is Rank & Folder’s consistent starting choice whenever this Mac meets its basic memory requirement. Mac fit is shown separately and does not make the starting choice change from one visit to the next.")
            HelpCallout(icon: "tablecells", text: "Choose Compare models to open a resizable table. Read down one model or across one criterion to compare purpose, speed, download size, memory, fit, strength, limit, license, and current status.")
            HelpCallout(icon: "scope", text: "The highlighted Why choose it row explains what each model adds to Rank & Folder itself. The category labels remain visible while you scroll across models.")
            HelpCallout(icon: "cursorarrow.click.2", text: "When Ollama reports more than one supported model, use the Model to use for layouts menu. Rank & Folder does not switch models merely because another model starts running.")
            HelpCallout(icon: "arrow.triangle.2.circlepath", text: "Runner and installed-model status refresh automatically. Rank & Folder lets an active check finish before starting another, so a slower response is not cancelled by the timer. After all three steps are ready, folder selection remains available at the bottom while every model card stays visible.")
            HelpCallout(icon: "folder.badge.plus", text: "If one supported model is already installed, Choose a folder stays available while you review or install another model. Rank & Folder names the model that will be used before you continue.")
            HelpCallout(icon: "terminal", text: "Rank & Folder never runs the existing-Ollama Terminal commands for you. Copy is explicit, and the official Ollama instructions remain linked beside setup.")
            HelpCallout(icon: "arrow.clockwise", text: "If a model returns unusable data, Rank & Folder retries with a stricter request. A clear error and model-change action remain available if every attempt fails.")
            HelpCallout(icon: "cpu", text: "The optional Mac check reads only coarse processor, memory, macOS, and free-space information. Fit labels are estimates. You can skip the check and browse every model yourself.")

        case .appearance:
            HelpIntro("Rank & Folder can follow your Mac or use a light or dark appearance. Text size and color vision support are separate choices.")
            HelpSteps(steps: [
                ("Open Appearance", "Click the Settings button in the Rank & Folder toolbar, or choose RankFolder → Settings."),
                ("Choose a text size", "Larger is the starting size. Choose Standard or Largest for the most comfortable reading size."),
                ("Choose a theme", "System follows your Mac automatically. Light and Dark keep Rank & Folder in the appearance you choose without changing Finder."),
                ("Choose color vision support", "Choose Standard colors, Red-green color vision deficiency, Blue-yellow color vision deficiency, or Complete color vision deficiency.")
            ])
            HelpCallout(icon: "text.cursor", text: "Explanatory text in Rank & Folder can be selected and copied with the usual Command-C shortcut.")
            HelpCallout(icon: "eye", text: "The red-green choice covers deuteranomaly, protanomaly, deuteranopia, and protanopia. The blue-yellow choice covers tritanomaly and tritanopia. The complete color vision choice covers monochromacy and achromatopsia.")
            HelpCallout(icon: "checkmark.circle", text: "Color is never the only way Rank & Folder communicates status. Every important state also uses words and a distinct symbol.")

        case .privacy:
            HelpIntro("Rank & Folder asks at the moment a feature needs access and limits what it does with that access.")
            HelpDefinition(title: "Selected folders", example: "Saved paths and an opaque read-only folder identity stay in local app preferences. The identity helps Rank & Folder notice if a folder was replaced. Folder previews read immediate visible names and standard metadata while open; they never read file contents or scan subfolders recursively. Older saved folders can be removed and added again to gain the identity check.", icon: "folder")
            HelpDefinition(title: "Protected folders", example: "macOS may separately ask to allow access to Downloads, Documents, Desktop, a cloud folder, network drive, or removable drive after you add it. Rank & Folder uses that access only for the selected folder’s names and standard metadata. Revoke a folder category in System Settings → Privacy & Security → Files & Folders.", icon: "folder.badge.questionmark")
            HelpDefinition(title: "Accessibility", example: "Needed only to identify the focused Finder folder and operate Finder’s existing view controls. macOS grants this broad permission; Rank & Folder deliberately uses a narrow subset.", icon: "accessibility")
            HelpDefinition(title: "Mac compatibility check", example: "This is Rank & Folder’s own consent, not a System Settings permission. The check happens locally and raw specs are not saved. Turn it off in Models at any time.", icon: "cpu")
            HelpDefinition(title: "Models", example: "Rank & Folder sends Ollama requests only to its local endpoint. Ollama’s own behavior and model sources apply. RankFolder does not offer a cloud model connection in this preview.", icon: "brain")
            HelpDefinition(title: "Local Network", example: "macOS may ask for Local Network access when you choose Ollama. Rank & Folder uses it only to reach Ollama on this Mac. Revoke it under System Settings → Privacy & Security → Local Network.", icon: "network")

        case .accessibility:
            HelpIntro("Accessibility approval follows one exact copy of an app.")
            HelpSteps(steps: [
                ("Use the Applications copy", "Move Rank & Folder to Applications, quit any other copy, then reopen it from Applications."),
                ("Remove an old approval", "Open System Settings → Privacy & Security → Accessibility. If Rank & Folder is already listed but the app cannot recognize it, remove that row."),
                ("Add this copy", "Click +, choose /Applications/Rank & Folder.app, and turn it on."),
                ("Return to Rank & Folder", "Use Check Again in the setup card. You normally do not need to restart the Mac.")
            ])
            HelpCallout(icon: "info.circle", text: "Layouts with extra levels use Folder preview and do not require Accessibility. Applying a simple layout inside Finder does.")

        case .shortcuts:
            HelpIntro("Common actions are available from the keyboard.")
            HelpShortcut(keys: "⌘N", action: "Add a folder")
            HelpShortcut(keys: "Delete", action: "Ask to remove the selected saved layout")
            HelpShortcut(keys: "⌘?", action: "Open Rank & Folder help")
            HelpShortcut(keys: "Return", action: "Continue through the welcome tour")
            Text("All important actions are also labeled on screen and have VoiceOver names. Color is never the only status signal.")

        case .safety:
            HelpIntro("Rank & Folder is source-available so its behavior can be inspected and independently built for uses allowed by its license.")
            HelpDefinition(title: "What it can change", example: "A saved profile and Finder’s existing view controls. Folder previews are read-only.", icon: "slider.horizontal.3")
            HelpDefinition(title: "What it does not do", example: "No file-content reading, hidden .DS_Store editing, arbitrary command execution, keystroke logging, screen capture, analytics, or telemetry. Existing-Ollama commands are copied only when you choose Copy.", icon: "nosign")
            HelpDefinition(title: "Optional networking", example: "Choosing layouts yourself needs no model connection. While the local-model path is selected, Rank & Folder checks Ollama on this Mac for current runner and model status. Folder summaries are sent only after you ask for a layout. No cloud model connection is available in this preview.", icon: "network")
            HelpDefinition(title: "Reset Rank & Folder", example: "Open Rank & Folder → Settings → Reset. Review the required reset items, then separately choose whether to remove RankFolder’s Ollama program or its managed models. A final screen lists exactly what will happen. Your files and separate Ollama installations are never changed.", icon: "arrow.counterclockwise")
            HelpDefinition(title: "License", example: "Rank & Folder uses the PolyForm Noncommercial License 1.0.0. Open About RankFolder for the official terms and the project’s GitHub releases.", icon: "doc.text")
            HelpCallout(icon: "lock.shield", text: "No software can be proven completely safe. Review SECURITY.md and the source before granting broad macOS permissions.")
        }
    }
}

private struct HelpIntro: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).rankFolderFont(.title3).foregroundStyle(.secondary)
    }
}

private struct HelpSteps: View {
    let steps: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 13) {
                    Text("\(index + 1)")
                        .rankFolderFont(.callout, weight: .bold)
                        .frame(width: 28, height: 28)
                        .background(RankFolderPalette.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.0).rankFolderFont(.headline, weight: .semibold)
                        Text(step.1).rankFolderFont(.body).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct HelpDefinition: View {
    let title: String
    let example: String
    let icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .rankFolderFont(.title3)
                .foregroundStyle(RankFolderPalette.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).rankFolderFont(.headline, weight: .semibold)
                Text(example).rankFolderFont(.body).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HelpCallout: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .rankFolderFont(.body)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RankFolderPalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HelpShortcut: View {
    let keys: String
    let action: String
    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(keys)
                .rankFolderFont(.body, weight: .semibold, design: .monospaced)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
    }
}

struct RankFolderCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let onboarding: OnboardingStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Rank & Folder") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button("Rank & Folder help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: [.command])
            Button("Show welcome tour") {
                onboarding.presentWalkthrough()
                openWindow(id: "tour")
            }
            Divider()
        }
    }
}

struct RankFolderAboutView: View {
    private let releasesURL = URL(string: "https://github.com/drabhikroy/rank-and-folder/releases")!
    private let licenseURL = URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityHidden(true)

                VStack(spacing: 5) {
                    Text("Rank & Folder")
                        .rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
                    Text("Version \(version) · Build \(build)")
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Project", systemImage: "shippingbox")
                            .rankFolderFont(.title3, weight: .semibold)
                        Text("Rank & Folder is source-available software that gives each saved folder its own layout while Finder stays the primary file browser.")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                        Link("View releases on GitHub", destination: releasesURL)
                            .rankFolderFont(.body, weight: .semibold)
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("License", systemImage: "doc.text")
                            .rankFolderFont(.title3, weight: .semibold)
                        Text("PolyForm Noncommercial License 1.0.0")
                            .rankFolderFont(.body, weight: .semibold)
                        Text("Commercial use is not permitted by this license. Follow the complete terms when using or sharing the source.")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                        Link("Read the license terms", destination: licenseURL)
                            .rankFolderFont(.body, weight: .semibold)
                    }
                }

                Text("Copyright 2026 Abhik Roy")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 440)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .background(RankFolderBackdrop())
        .textSelection(.enabled)
    }
}
