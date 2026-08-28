import AppKit
import Combine
import SwiftUI

/// The main window. A sidebar lists every saved folder and every folder marked
/// as left alone, and the detail side shows the home screen, one folder's
/// layout editor, or one boundary.
struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.rankFolderPanelSpacing) private var panelSpacing
    @EnvironmentObject private var onboarding: OnboardingStore
    @ObservedObject var store: ProfileStore
    @ObservedObject var automation: AutomationCoordinator
    @State private var selection: SidebarSelection? = .home
    @State private var pendingRemoval: PendingRemoval?
    @State private var isChoosingFolder = false
    @State private var checkedFirstLaunch = false
    @State private var folderSearch = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 620)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    workToolbarBubble
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarSpacer(.fixed, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    appToolbarBubble
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 10) {
                        workToolbarBubble
                        appToolbarBubble
                    }
                }
            }
        }
        .alert(removalTitle, isPresented: removalAlertIsPresented) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button(removalButtonTitle, role: .destructive, action: removePendingItem)
        } message: {
            Text(removalMessage)
        }
        .onDeleteCommand(perform: requestSelectedRemoval)
        .onAppear {
            if onboarding.suggestionMethod != .off {
                ModelCenterViewModel.shared.startMonitoring()
            }
            if selection == nil { selection = .home }
            automation.refreshSetupStatus()
            guard !checkedFirstLaunch else { return }
            checkedFirstLaunch = true
            if onboarding.shouldShowAutomatically(hasExistingProfiles: !store.profiles.isEmpty) {
                onboarding.presentWalkthrough()
                openWindow(id: "tour")
            }
        }
        .onChange(of: onboarding.isWalkthroughPresented) { _, isPresented in
            if isPresented {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "tour")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rankFolderSelectProfile)) { note in
            if let profileID = note.object as? UUID {
                selection = .profile(profileID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            automation.refreshSetupStatus()
            if onboarding.suggestionMethod != .off {
                ModelCenterViewModel.shared.checkOllama(showChecking: false)
            }
        }
        .onChange(of: onboarding.suggestionMethod) { _, method in
            if method == .off {
                ModelCenterViewModel.shared.stopMonitoring()
            } else {
                ModelCenterViewModel.shared.startMonitoring()
            }
        }
        .onChange(of: store.profiles.map(\.id)) { _, ids in
            if selection == nil {
                selection = fallbackSelection
            } else if case .profile(let selectedID) = selection,
                      !ids.contains(selectedID) {
                selection = fallbackSelection
            }
        }
        .onChange(of: store.boundaries.map(\.id)) { _, ids in
            if case .boundary(let selectedID) = selection,
               !ids.contains(selectedID) {
                selection = fallbackSelection
            }
        }
    }

    private var workToolbarBubble: some View {
        ToolbarActionBubble {
            Button(action: addFolder) {
                Label("Add folder", systemImage: "folder.badge.plus")
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .disabled(isChoosingFolder)
            .help("Add a folder and save how it should be organized")
            .accessibilityHint("Opens a folder chooser. Your files will not be changed.")
            .keyboardShortcut("n", modifiers: [.command])

            Button {
                openWindow(id: "models")
            } label: {
                Label("Models", systemImage: "cpu")
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Choose whether Rank & Folder uses a local model")
        }
    }

    private var appToolbarBubble: some View {
        ToolbarActionBubble {
            Button {
                openWindow(id: "settings")
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Open Rank & Folder settings")

            Button {
                openWindow(id: "help")
            } label: {
                Label("Help", systemImage: "questionmark.circle")
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Open Rank & Folder help")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(SidebarSelection.home)
                    .accessibilityHint("Open the Rank & Folder overview and getting-started guide.")
            }

            if store.profiles.isEmpty {
                Section("Saved folders") {
                    Text("Add a folder to create your first layout.")
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
            } else if filteredProfiles.isEmpty {
                Section("Saved folders") {
                    ContentUnavailableView.search(text: folderSearch)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(FolderLocationGroup.allCases) { group in
                    let profiles = filteredProfiles.filter { group.contains($0.folderURL) }
                    if !profiles.isEmpty {
                        Section(group.title) {
                            ForEach(profiles) { profile in
                                ProfileRow(profile: profile)
                                    .tag(SidebarSelection.profile(profile.id))
                                    .contextMenu {
                                        Button("Open in Finder") {
                                            NSWorkspace.shared.open(profile.folderURL)
                                        }
                                        Divider()
                                        Button("Remove saved layout…", role: .destructive) {
                                            pendingRemoval = .profile(profile.id)
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            if !store.boundaries.isEmpty {
                Section("Folders left alone") {
                    ForEach(store.boundaries) { boundary in
                        BoundaryRow(boundary: boundary)
                            .tag(SidebarSelection.boundary(boundary.id))
                            .contextMenu {
                                Button("Open in Finder") {
                                    NSWorkspace.shared.open(boundary.folderURL)
                                }
                                Divider()
                                Button("Allow saved layouts here again…", role: .destructive) {
                                    pendingRemoval = .boundary(boundary.id)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $folderSearch, prompt: "Find a saved folder")
        .navigationTitle("Rank & Folder")
        .navigationSplitViewColumnWidth(min: 285, ideal: sidebarPreferredWidth, max: 420)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6 * panelSpacing) {
                // Icon and word ran together across the two buttons, so the row
                // read as one phrase rather than as two controls. Each button
                // now shows only its symbol, the pair is boxed as a group the
                // way a source list footer is on this platform, and the words
                // stay on the tooltip and the accessibility label.
                HStack(spacing: 0) {
                    Button(action: addFolder) {
                        Image(systemName: "plus")
                            .frame(width: 30, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(isChoosingFolder)
                    .help("Add a folder")
                    .accessibilityLabel("Add a folder")

                    Divider().frame(height: 16)

                    Button(action: requestSelectedRemoval) {
                        Image(systemName: "minus")
                            .frame(width: 30, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!selectionCanBeRemoved)
                    .help(removeButtonHelp)
                    .accessibilityLabel(removeButtonLabel)
                    .accessibilityHint("Shows a confirmation before changing Rank & Folder’s saved choices.")
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                HStack(spacing: 8) {
                    Label(
                        automation.setupComplete ? "Automation on" : "Automation off",
                        systemImage: automation.setupComplete
                            ? "checkmark.circle"
                            : "circle.slash"
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(automation.setupComplete
                        ? "Optional Finder automation is on"
                        : "Rank & Folder is ready; optional Finder automation is off")
                    Spacer(minLength: 8)
                    Text("Rank & Folder \(appVersion)")
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
            }
            .rankFolderFont(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10 * panelSpacing)
            .padding(.vertical, 8 * panelSpacing)
            .background(.bar)
        }
    }

    /// A fixed ideal width. Measuring saved folder names and feeding the result
    /// back as the ideal width made the column jump whenever a folder was added
    /// or removed, discarding a width the person had dragged. The person can
    /// still resize between the declared minimum and maximum.
    private var sidebarPreferredWidth: CGFloat { 320 }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var filteredProfiles: [RankFolderProfile] {
        let query = folderSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.profiles
            .filter { profile in
                query.isEmpty
                    || profile.displayName.localizedCaseInsensitiveContains(query)
                    || profile.folderPath.localizedCaseInsensitiveContains(query)
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    @ViewBuilder
    private var detail: some View {
        if selection == .home {
            HomeView(
                profiles: store.profiles,
                automation: automation,
                onboarding: onboarding,
                errorMessage: store.lastError,
                addFolder: addFolder,
                selectProfile: { selection = .profile($0) },
                showWalkthrough: onboarding.presentWalkthrough,
                showModels: { openWindow(id: "models") }
            )
        } else if case .profile(let profileID) = selection,
           let profile = store.profile(id: profileID) {
            ProfileEditorView(
                profile: profile,
                store: store,
                automation: automation
            )
            .id(profile.id)
        } else if case .boundary(let boundaryID) = selection,
                  let boundary = store.boundary(id: boundaryID) {
            BoundaryDetailView(
                boundary: boundary,
                allowLayoutsAgain: { pendingRemoval = .boundary(boundary.id) }
            )
            .id(boundary.id)
        } else {
            SelectProfileView()
        }
    }

    private var removalAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private var removalTitle: String {
        switch pendingRemoval {
        case .profile(let id):
            guard let profile = store.profile(id: id) else {
                return "Remove this saved layout?"
            }
            return "Remove “\(profile.displayName)” from Rank & Folder?"
        case .boundary(let id):
            guard let boundary = store.boundary(id: id) else {
                return "Allow saved layouts here again?"
            }
            return "Allow saved layouts in “\(boundary.displayName)” again?"
        case nil:
            return "Remove this saved choice?"
        }
    }

    private var removalButtonTitle: String {
        switch pendingRemoval {
        case .profile: "Remove layout"
        case .boundary: "Allow layouts again"
        case nil: "Remove"
        }
    }

    private var removalMessage: String {
        switch pendingRemoval {
        case .profile(let id):
            guard let profile = store.profile(id: id) else {
                return "Its saved layout will be removed. A layout from a higher folder may be used here afterward. The folder and everything inside it will stay on your Mac."
            }
            if profile.descendantScope == .descendants {
                return "This saved layout will be removed from \(profile.displayName) and its subfolders. The closest layout from a higher folder may be used afterward unless a subfolder has its own saved choice or is left alone. No files or existing Finder views will be changed."
            }
            return "This saved layout will be removed. The closest layout from a higher folder may be used in \(profile.displayName) afterward. The folder and everything inside it will stay on your Mac."
        case .boundary(let id):
            let name = store.boundary(id: id)?.displayName ?? "this folder"
            return "After this choice is removed, the closest saved layout from another folder may be used in \(name) and its subfolders. No files or existing Finder views will be changed."
        case nil:
            return "No files will be removed."
        }
    }

    private func addFolder() {
        guard !isChoosingFolder else { return }
        isChoosingFolder = true
        Task { @MainActor in
            defer { isChoosingFolder = false }
            guard let profileID = await FolderProfileCreationCoordinator.chooseAndAdd(
                to: store
            ) else { return }
            selection = .profile(profileID)
            automation.resetStatus()
        }
    }

    private func requestSelectedRemoval() {
        guard let selection else { return }
        switch selection {
        case .home:
            return
        case .profile(let id):
            pendingRemoval = .profile(id)
        case .boundary(let id):
            pendingRemoval = .boundary(id)
        }
    }

    private func removePendingItem() {
        switch pendingRemoval {
        case .profile(let id):
            store.remove(id: id)
            if selection == .profile(id) {
                selection = fallbackSelection
            }
        case .boundary(let id):
            store.removeBoundary(id: id)
            if selection == .boundary(id) {
                selection = fallbackSelection
            }
        case nil:
            break
        }
        pendingRemoval = nil
        automation.resetStatus()
    }

    private var fallbackSelection: SidebarSelection? {
        .home
    }

    private var selectionCanBeRemoved: Bool {
        switch selection {
        case .profile, .boundary: true
        case .home, nil: false
        }
    }

    private var removeButtonLabel: String {
        switch selection {
        case .home: "Home cannot be removed"
        case .profile: "Remove selected saved layout"
        case .boundary: "Allow saved layouts in the selected folder again"
        case nil: "Remove selected saved choice"
        }
    }

    private var removeButtonHelp: String {
        switch selection {
        case .home: "Select a saved folder or a folder left alone"
        case .profile: "Remove the selected saved layout"
        case .boundary: "Allow a saved layout from another folder to be used here again"
        case nil: "Select a saved folder or a folder left alone"
        }
    }
}

/// Groups a pair of toolbar buttons into one rounded control, so the two work
/// actions and the two application actions read as two groups rather than four
/// loose buttons.
private struct ToolbarActionBubble<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        // A material here samples the window behind it and renders as a grey
        // slab in light appearance, which reads as a disabled control. The
        // control background color stays close to the toolbar in both
        // appearances, so the capsule reads as a grouped control instead.
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9), in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

/// What the sidebar currently has selected. Profiles and boundaries are both
/// identified by their own identifier, so a selection survives the list being
/// resorted.
private enum SidebarSelection: Hashable {
    case home
    case profile(UUID)
    case boundary(UUID)
}

/// The sidebar heading a saved folder is filed under, decided from where the
/// folder lives rather than from anything the person chose.
private enum FolderLocationGroup: Int, CaseIterable, Identifiable {
    case onMyMac
    case iCloudDrive
    case cloudStorage
    case externalOrNetwork
    case other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .onMyMac: "On my Mac"
        case .iCloudDrive: "iCloud Drive"
        case .cloudStorage: "Cloud storage"
        case .externalOrNetwork: "External and network"
        case .other: "Other locations"
        }
    }

    func contains(_ url: URL) -> Bool {
        Self.group(for: url) == self
    }

    private static func group(for url: URL) -> Self {
        let path = url.standardizedFileURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path.contains("/Library/Mobile Documents/com~apple~CloudDocs/") {
            return .iCloudDrive
        }
        if path.contains("/Library/CloudStorage/") {
            return .cloudStorage
        }
        if path == homePath || path.hasPrefix(homePath + "/") {
            return .onMyMac
        }
        if path == "/Volumes" || path.hasPrefix("/Volumes/") {
            return .externalOrNetwork
        }
        return .other
    }
}

/// The item a removal confirmation is currently asking about. Nil means no
/// confirmation is showing.
private enum PendingRemoval: Equatable {
    case profile(UUID)
    case boundary(UUID)
}

/// The single supported folder-picking and profile-creation flow used by both
/// the main window and first-run walkthrough.
@MainActor
enum FolderProfileCreationCoordinator {
    static func chooseAndAdd(to store: ProfileStore) async -> UUID? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder"
        panel.message = "Rank & Folder will save a layout for this folder. If it already uses a layout from another folder, Rank & Folder starts with a separate copy you can edit. Your files will not be changed."
        panel.prompt = "Add folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        // runModal blocks the main actor for as long as the chooser is open,
        // which stalls every other main-actor task behind it. begin returns
        // immediately and delivers its answer through the continuation.
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let folderURL = panel.url else { return nil }
        return await store.add(folderURL: folderURL)
    }
}

/// One saved folder in the sidebar, showing its name, where it lives, and
/// whether its layout is paused.
private struct ProfileRow: View {
    let profile: RankFolderProfile

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(profile.isEnabled
                        ? RankFolderPalette.accent.opacity(0.14)
                        : Color.secondary.opacity(0.10))
                Image(systemName: profile.isEnabled ? "folder.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(profile.isEnabled ? RankFolderPalette.accent : Color.secondary)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(profile.isEnabled ? rowSummary : "Paused · no layout here or below")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.displayName), \(profile.isEnabled ? "active" : "paused")")
        .accessibilityValue(
            profile.isEnabled
                ? rowSummary
                : "Rank & Folder leaves this folder and its subfolders alone"
        )
        .accessibilityHint("Select to view and edit this saved layout.")
    }

    private var rowSummary: String {
        let sections = profile.recipe.sections.count
        let order = profile.recipe.itemOrder.first?.criterion.displayName ?? "Name"
        let layout = sections == 0
            ? "One list · \(order)"
            : "\(sections) section \(sections == 1 ? "level" : "levels") · \(order)"
        return profile.descendantScope == .descendants
            ? "\(layout) · Includes subfolders"
            : layout
    }
}

/// One folder marked as left alone in the sidebar. These are listed separately
/// from saved folders because they carry no layout of their own.
private struct BoundaryRow: View {
    let boundary: FolderInheritanceBoundary

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                Image(systemName: "folder.badge.minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(boundary.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("No saved layout here")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(boundary.displayName), no saved layout here")
        .accessibilityValue("Rank & Folder leaves this folder and its subfolders alone")
        .accessibilityHint("Select to review this choice or allow saved layouts here again.")
    }
}

/// The detail side for a folder marked as left alone. It explains what the mark
/// does and offers the one action that removes it.
private struct BoundaryDetailView: View {
    let boundary: FolderInheritanceBoundary
    let allowLayoutsAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(boundary.displayName, systemImage: "folder.badge.minus")
                        .rankFolderFont(.largeTitle, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(boundary.folderPath)
                        .rankFolderFont(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Rank & Folder leaves this folder alone", systemImage: "hand.raised.fill")
                            .rankFolderFont(.title2, weight: .semibold)
                        Text("A saved layout from another folder stops here. Rank & Folder also leaves subfolders alone unless a deeper folder has its own saved layout.")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                boundaryActions
                            }
                            .fixedSize(horizontal: true, vertical: false)

                            VStack(alignment: .leading, spacing: 10) {
                                boundaryActions
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(boundary.displayName)
    }

    @ViewBuilder
    private var boundaryActions: some View {
        Button("Open folder in Finder") {
            NSWorkspace.shared.open(boundary.folderURL)
        }
        .controlSize(.large)

        Button("Allow saved layouts again…", action: allowLayoutsAgain)
            .controlSize(.large)
            .accessibilityHint("Shows a confirmation because a layout from another folder may begin applying here again.")
    }
}

/// The detail side when nothing is selected. It carries the introduction, the
/// two starting choices, and a short list of saved folders.
private struct HomeView: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    @ObservedObject private var modelAvailability = ModelCenterViewModel.shared
    let profiles: [RankFolderProfile]
    @ObservedObject var automation: AutomationCoordinator
    @ObservedObject var onboarding: OnboardingStore
    let errorMessage: String?
    let addFolder: () -> Void
    let selectProfile: (UUID) -> Void
    let showWalkthrough: () -> Void
    let showModels: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero

                primaryChoices

                if !profiles.isEmpty {
                    savedFolders
                }

                reassurance

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .rankFolderFont(.callout)
                        .foregroundStyle(colorVisionMode.color(for: .danger))
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(RankFolderBackdrop())
        .navigationTitle("Home")
    }

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                heroWords
                Spacer(minLength: 16)
                FolderLayoutIllustration()
            }
            VStack(alignment: .leading, spacing: 22) {
                heroWords
                FolderLayoutIllustration().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    RankFolderPalette.action.opacity(0.14),
                                    RankFolderPalette.coral.opacity(0.07),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }

        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var heroWords: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rank & Folder")
                .rankFolderFont(.caption, weight: .bold)
                .tracking(1.6)
                .foregroundStyle(RankFolderPalette.accent)
            Text(profiles.isEmpty ? "One Finder. Different rules for every folder." : "Welcome back")
                .rankFolderFont(.largeTitle, weight: .semibold, design: .rounded)
                .accessibilityAddTraits(.isHeader)
            Text("Save a different way to group and sort each folder.")
                .rankFolderFont(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: showWalkthrough) {
                Label("Quick tour", systemImage: "play.circle")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 500, alignment: .leading)
    }

    private var primaryChoices: some View {
        Grid(horizontalSpacing: 16) {
            GridRow(alignment: .top) {
                choiceCards
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var choiceCards: some View {
        HomeChoiceCard(
            eyebrow: "Start here",
            title: profiles.isEmpty ? "Organize a folder" : "Add another folder",
            detail: "Choose a folder, then build its layout yourself or ask a local model for a starting point.",
            icon: "folder.fill.badge.plus",
            tint: RankFolderPalette.action,
            buttonTitle: profiles.isEmpty ? "Choose a folder" : "Add a folder",
            action: addFolder
        )

        HomeChoiceCard(
            eyebrow: "Optional",
            title: "Local model",
            detail: localModelStatus,
            icon: "cpu",
            tint: RankFolderPalette.coral,
            buttonTitle: "Choose model setup",
            action: showModels
        )
    }

    private var localModelStatus: String {
        guard onboarding.suggestionMethod != .off else {
            return "Off. You choose every layout yourself."
        }
        guard modelAvailability.isConnected else {
            return "Setup is not finished. Open Models to start or connect Ollama."
        }
        let name = LocalModelDescriptor.catalog.first {
            $0.id == modelAvailability.selectedModelID
        }?.name ?? "The selected model"
        return modelAvailability.selectedModelIsInstalled
            ? "\(name) is ready to create layouts for you to review."
            : "\(name) is selected but still needs to be downloaded."
    }

    private var savedFolders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved folders")
                .rankFolderFont(.title2, weight: .semibold)

            SurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(profiles.prefix(4).enumerated()), id: \.element.id) { index, profile in
                        Button {
                            selectProfile(profile.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(RankFolderPalette.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .fontWeight(.medium)
                                    Text(Self.summary(for: profile))
                                        .rankFolderFont(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .rankFolderFont(.caption, weight: .semibold)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open and edit this folder’s saved layout.")

                        if index < min(profiles.count, 4) - 1 {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
            }
        }
    }

    private var reassurance: some View {
        Label(
            "Rank & Folder never reads file contents or changes your files.",
            systemImage: "hand.raised.fill"
        )
        .rankFolderFont(.body)
        .foregroundStyle(.secondary)
    }

    private static func summary(for profile: RankFolderProfile) -> String {
        let sections = profile.recipe.sections.count
        let order = profile.recipe.itemOrder.first?.criterion.displayName ?? "Name"
        return sections == 0
            ? "One list, ordered by \(order)"
            : "\(sections) section \(sections == 1 ? "level" : "levels"), ordered by \(order)"
    }
}

/// One of the two starting choices on the home screen. The whole card is the
/// button; the capsule inside it is the visible target.
private struct HomeChoiceCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow)
                        .rankFolderFont(.caption2, weight: .bold)
                        .tracking(1.1)
                        .foregroundStyle(tint)
                    Text(title)
                        .rankFolderFont(.title2, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .rankFolderFont(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 7) {
                    Text(buttonTitle).fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(tint, in: Capsule())
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .accessibilityLabel("\(title). \(buttonTitle)")
        .accessibilityHint(detail)
    }
}

/// A drawing of two stacked folder cards beside the introduction. It shows no
/// real data and is hidden from assistive technology.
private struct FolderLayoutIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 188, height: 132)
                .rotationEffect(.degrees(-4))
                .offset(x: -8, y: 3)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .frame(width: 188, height: 132)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Projects", systemImage: "folder.fill")
                            .rankFolderFont(.headline, weight: .semibold)
                            .foregroundStyle(RankFolderPalette.accent)
                        ForEach([0.82, 0.62, 0.72], id: \.self) { width in
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 120 * width, height: 7)
                        }
                    }
                    .padding(20)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        }
        .frame(width: 210, height: 165)
        .accessibilityHidden(true)
    }
}

/// The detail side when the sidebar selection points at a folder that is no
/// longer there.
private struct SelectProfileView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Choose a folder", systemImage: "sidebar.left")
        } description: {
            Text("Select a saved folder in the sidebar to view or edit its organization.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
