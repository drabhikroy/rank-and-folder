import AppKit
import SwiftUI

/// The editor for one saved folder. It moves through building the layout,
/// choosing how far the layout reaches into subfolders, and choosing whether
/// Finder is driven automatically.
struct ProfileEditorView: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    @Environment(\.rankFolderPanelSpacing) private var panelSpacing
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var onboarding: OnboardingStore
    @ObservedObject private var modelAvailability = ModelCenterViewModel.shared
    let profile: RankFolderProfile
    @ObservedObject var store: ProfileStore
    @ObservedObject var automation: AutomationCoordinator
    @State private var scopeUndo: ScopeUndo?
    @State private var pendingBoundaryURL: URL?
    @State private var isResolvingTarget = false
    @State private var selectedSettingsPanel = ProfileEditorPanel.subfolders
    @State private var showsFolderSettings = false
    @State private var selectedLayoutStage = LayoutEditorStage.sections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20 * panelSpacing) {
                folderHeader
                folderSettingsStep
                organizationCard

                if let error = store.lastError {
                    AutomationStatusBanner(status: .failed(error))
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 34 * panelSpacing)
            .padding(.vertical, 28 * panelSpacing)
            .frame(maxWidth: .infinity)
        }
        .background(RankFolderBackdrop())
        .navigationTitle(profile.displayName)
        .alert(boundaryConfirmationTitle, isPresented: boundaryConfirmationIsPresented) {
            Button("Cancel", role: .cancel) { pendingBoundaryURL = nil }
            Button("Leave these folders alone", role: .destructive) {
                createPendingBoundary()
            }
        } message: {
            Text(boundaryConfirmationMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rankFolderShowPreview)) { note in
            guard note.object as? UUID == profile.id else { return }
            selectedLayoutStage = .preview
            SecondaryWindowStore.shared.requestedPreviewProfileID = nil
        }
        .onAppear {
            if SecondaryWindowStore.shared.requestedPreviewProfileID == profile.id {
                selectedLayoutStage = .preview
                SecondaryWindowStore.shared.requestedPreviewProfileID = nil
            }
        }
    }

    private var folderSettingsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkflowStepHeader(
                number: 1,
                title: "Folder settings",
                detail: "Optional. The defaults keep this layout in this folder and leave Finder automation off."
            )

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsFolderSettings.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: showsFolderSettings ? "chevron.down" : "chevron.right")
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showsFolderSettings ? "Hide optional settings" : "Review optional settings")
                            .rankFolderFont(.body, weight: .semibold)
                        Text(folderSettingsSummary)
                            .rankFolderFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 13))

            if showsFolderSettings {
                Picker("Folder settings", selection: $selectedSettingsPanel) {
                    ForEach(ProfileEditorPanel.allCases) { panel in
                        Label(panel.title, systemImage: panel.systemImage).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .frame(maxWidth: 620)

                switch selectedSettingsPanel {
                case .subfolders: scopeCard
                case .finder: finderPanel
                }
            }
        }
    }

    private var folderSettingsSummary: String {
        let scope = profile.descendantScope == .descendants ? "Includes subfolders" : "This folder only"
        let finder = automation.setupComplete ? "Finder automation available" : "Finder automation off"
        return "\(scope) · \(finder)"
    }

    @ViewBuilder
    private var finderPanel: some View {
        if profile.finderRepresentation != nil && !automation.setupComplete {
            SetupChecklist(automation: automation, showFolderStep: false)
        }

        if automation.status.isVisible {
            AutomationStatusBanner(status: automation.status)
        }

        behaviorCard
    }

    private var folderHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                folderIdentity
                    .frame(minWidth: 360, alignment: .leading)
                Spacer(minLength: 16)
                folderHeaderActions
            }

            VStack(alignment: .leading, spacing: 14) {
                folderIdentity
                folderHeaderActions
            }
        }
    }

    private var folderIdentity: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(RankFolderPalette.accent.opacity(0.13))
                Image(systemName: "folder.fill")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(RankFolderPalette.accent)
            }
            .frame(width: 60, height: 60)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .rankFolderFont(.largeTitle, weight: .semibold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.folderPath)
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var folderHeaderActions: some View {
        Label(headerStatusTitle, systemImage: headerStatusIcon)
            .rankFolderFont(.callout, weight: .medium)
            .foregroundStyle(headerStatusTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerStatusTitle: String {
        if !profile.isEnabled { return "Paused" }
        return profile.requiresOrganizedView ? "Full preview available" : "Ready"
    }

    private var headerStatusIcon: String {
        if !profile.isEnabled { return "pause.circle.fill" }
        return profile.requiresOrganizedView
            ? "rectangle.3.group"
            : "checkmark.circle.fill"
    }

    private var headerStatusTint: Color {
        if !profile.isEnabled { return Color.secondary }
        return profile.requiresOrganizedView
            ? RankFolderPalette.accent
            : colorVisionMode.color(for: .success)
    }

    private var organizationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkflowStepHeader(
                number: 2,
                title: "How should this folder be organized?",
                detail: "Create helpful headings, choose what appears first, then review the result."
            )

            suggestionButton

            layoutStageNavigation

            switch selectedLayoutStage {
            case .sections:
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        stageHeading(
                            title: "Create sections",
                            detail: "Optional headings make a busy folder easier to scan.",
                            icon: "rectangle.split.3x1"
                        )
                        RecipeArea(
                            emptyText: "No sections. Show everything in one list.",
                            addTitle: "Add section",
                            rowNoun: "Section level",
                            levels: profile.recipe.sections,
                            canBeEmpty: true,
                            update: updateSection,
                            add: addSection,
                            move: moveSection,
                            remove: removeSection
                        )
                        stageFooter(back: nil, next: .itemOrder)
                    }
                }
                CompactFolderPreview(profile: profile)

            case .itemOrder:
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        stageHeading(
                            title: "Choose item order",
                            detail: "Pick what appears first. Add another rule only to break ties.",
                            icon: "arrow.up.arrow.down"
                        )
                        RecipeArea(
                            emptyText: "",
                            addTitle: "Add a tie-breaker",
                            rowNoun: "Order rule",
                            levels: profile.recipe.itemOrder,
                            canBeEmpty: false,
                            update: updateItemOrder,
                            add: addItemOrder,
                            move: moveItemOrder,
                            remove: removeItemOrder
                        )
                        if profile.recipe.allLevels.contains(where: { $0.direction == nil }) {
                            Label(
                                "Keep Finder’s current direction leaves its ascending or descending choice alone. Rank & Folder previews that choice as A to Z or oldest first.",
                                systemImage: "arrow.up.arrow.down.circle"
                            )
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                        }
                        stageFooter(back: .sections, next: .preview)
                    }
                }
                CompactFolderPreview(profile: profile)

            case .preview:
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        stageHeading(
                            title: "Preview and use it",
                            detail: "Check the result before opening anything.",
                            icon: "eye"
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            Text("What you will see")
                                .rankFolderFont(.callout, weight: .bold)
                                .tracking(0.8)
                                .foregroundStyle(RankFolderPalette.accent)
                            Text(recipeSummary)
                                .rankFolderFont(.title3, weight: .medium)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [
                                    RankFolderPalette.action.opacity(0.12),
                                    RankFolderPalette.coral.opacity(0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                        rendererNote
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { organizationActions }
                            VStack(alignment: .leading, spacing: 10) { organizationActions }
                        }
                        stageFooter(back: .itemOrder, next: nil)
                    }
                }
                CompactFolderPreview(profile: profile)
            }
        }
    }

    private var layoutStageNavigation: some View {
        HStack(spacing: 8) {
            ForEach(LayoutEditorStage.allCases) { stage in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedLayoutStage = stage
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: stage.systemImage)
                            .rankFolderFont(.callout, weight: .semibold)
                            .frame(width: 24, height: 24)
                            .background(
                                selectedLayoutStage == stage
                                    ? Color.white.opacity(0.20)
                                    : Color.primary.opacity(0.07),
                                in: Circle()
                            )
                        Text(stage.shortTitle).fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .foregroundStyle(selectedLayoutStage == stage ? Color.white : Color.primary)
                .background(
                    selectedLayoutStage == stage
                        ? RankFolderPalette.accent
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .accessibilityLabel(stage.shortTitle)
                .accessibilityValue(selectedLayoutStage == stage ? "Selected" : "")
            }
        }
        .padding(5)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 15))
    }

    private func stageHeading(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .rankFolderFont(.title2, weight: .medium)
                .foregroundStyle(RankFolderPalette.accent)
                .frame(width: 42, height: 42)
                .background(RankFolderPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).rankFolderFont(.title2, weight: .semibold)
                Text(detail).rankFolderFont(.body).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stageFooter(back: LayoutEditorStage?, next: LayoutEditorStage?) -> some View {
        Divider()
        HStack {
            if let back {
                Button("Back") { selectedLayoutStage = back }
            }
            Spacer()
            if let next {
                Button(next == .preview ? "Review layout" : "Continue") {
                    selectedLayoutStage = next
                }
                .buttonStyle(RankFolderPrimaryActionButtonStyle())
                .id(next)
            }
        }
    }

    @ViewBuilder
    private var suggestionButton: some View {
        if onboarding.suggestionMethod != .off,
           modelAvailability.selectedModelIsInstalled,
           modelAvailability.isConnected {
            Button {
                SecondaryWindowStore.shared.modelProfileID = profile.id
                openWindow(id: "model-layout")
            } label: {
                Label(modelButtonTitle, systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RankFolderModelActionButtonStyle())
            .controlSize(.large)
            .help("Ask the selected local model for an editable starting layout")
        } else {
            Button {
                openWindow(id: "models")
            } label: {
                Label("Set up an optional local model", systemImage: "cpu")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Set up an optional local model")
        }
    }

    private var modelButtonTitle: String {
        guard onboarding.suggestionMethod != .off,
              modelAvailability.isConnected,
              modelAvailability.selectedModelIsInstalled else {
            return "Ask a local model to suggest a layout"
        }
        let name = LocalModelDescriptor.catalog.first {
            $0.id == modelAvailability.selectedModelID
        }?.name ?? "Local model"
        return "Ask \(name) for a layout"
    }

    @ViewBuilder
    private var organizationActions: some View {
        if profile.finderRepresentation != nil {
            if automation.setupComplete {
                Button {
                    if let current = store.profile(id: profile.id) {
                        automation.applyNow(current)
                    }
                } label: {
                    Label("Open in Finder and apply", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!profile.isEnabled)
                .help("Open this folder and apply the complete plan in Finder")

                Button {
                    presentOrganizedView(for: profile.folderURL)
                } label: {
                    Label("Preview in Rank & Folder", systemImage: "eye")
                }
                .controlSize(.large)
                .help("Preview this layout without changing Finder")
            } else {
                Button {
                    presentOrganizedView(for: profile.folderURL)
                } label: {
                    Label("Preview in Rank & Folder", systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Preview this layout without changing Finder or requiring Accessibility")

                Button("Set up Finder automation…") {
                    selectedSettingsPanel = .finder
                    showsFolderSettings = true
                }
                .controlSize(.large)
                .help("Optional: allow Rank & Folder to restore this layout inside Finder")
            }
        } else {
            Button {
                presentOrganizedView(for: profile.folderURL)
            } label: {
                Label("Open folder preview", systemImage: "rectangle.3.group")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Show every saved section and order rule")
        }

        Button("Open folder in Finder") {
            NSWorkspace.shared.open(profile.folderURL)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var rendererNote: some View {
        if profile.finderRepresentation != nil {
            Label(
                automation.setupComplete
                    ? "This layout fits Finder, and optional Finder automation can restore it when this folder opens."
                    : "This layout fits Finder, but no permission is required to preview it in Rank & Folder. Finder automation is optional.",
                systemImage: "finder"
            )
            .rankFolderFont(.callout)
            .foregroundStyle(.secondary)
        } else {
            Label(
                "Finder can show only one section level and one order rule. Rank & Folder can show every saved level in a read-only full preview; your files still open in Finder.",
                systemImage: "info.circle.fill"
            )
            .rankFolderFont(.callout)
            .foregroundStyle(colorVisionMode.color(for: .information))
            .padding(12)
            .background(RankFolderPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var behaviorCard: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: behaviorIcon)
                    .rankFolderFont(.title2)
                    .foregroundStyle(behaviorTint)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(behaviorTitle).rankFolderFont(.headline, weight: .semibold)
                    Text(behaviorDetail)
                        .rankFolderFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 20)

                if profile.finderRepresentation != nil
                    && !automation.requiresManualApply(profile)
                    && automation.setupComplete {
                    Toggle("Restore automatically", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .help(profile.descendantScope == .descendants
                            ? "Restore this layout here and in subfolders without their own saved choice"
                            : "Restore this plan whenever Finder opens this folder")
                        .accessibilityLabel("Restore automatically")
                        .accessibilityValue(profile.isEnabled ? "On" : "Off")
                        .accessibilityHint(profile.descendantScope == .descendants
                            ? "Controls this folder and subfolders that use its layout."
                            : "Controls this folder only.")
                } else if profile.finderRepresentation != nil
                    && !automation.requiresManualApply(profile) {
                    Label("Finder automation off", systemImage: "circle.slash")
                        .rankFolderFont(.callout, weight: .medium)
                        .foregroundStyle(.secondary)
                } else if profile.requiresOrganizedView {
                    Label("Saved locally", systemImage: "checkmark.circle")
                        .rankFolderFont(.callout, weight: .medium)
                        .foregroundStyle(RankFolderPalette.accent)
                }
            }
        }
    }

    private var scopeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            scopeHeading
                                .frame(minWidth: 285, alignment: .leading)
                            Spacer(minLength: 20)
                            scopeToggle
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            scopeHeading
                            scopeToggle
                        }
                    }
                }

                if profile.descendantScope == .descendants {
                    Divider()

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            subfolderActionButtons
                            Spacer()
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        VStack(alignment: .leading, spacing: 10) {
                            subfolderActionButtons
                        }
                    }
                }

                if let scopeUndo {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            scopeUndoLabel(scopeUndo)
                            Spacer()
                            scopeUndoButton(scopeUndo)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            scopeUndoLabel(scopeUndo)
                            scopeUndoButton(scopeUndo)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                }

                Label(
                    "Including subfolders does not scan them or change files. Rank & Folder checks a folder only when you open or preview it.",
                    systemImage: "hand.raised"
                )
                .rankFolderFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopeHeading: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .rankFolderFont(.title2)
                .foregroundStyle(RankFolderPalette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Where should this layout be used?")
                    .rankFolderFont(.title2, weight: .semibold)
                Text(profile.descendantScope == .descendants
                    ? "A subfolder uses this layout unless it has its own saved layout or is set to be left alone."
                    : "This layout currently stays in this folder. Turn on subfolder use only if related folders should share it.")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var scopeToggle: some View {
        Toggle("Use this layout in subfolders", isOn: descendantScopeBinding)
            .toggleStyle(.switch)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityValue(
                profile.descendantScope == .descendants
                    ? "On, this folder and its subfolders"
                    : "Off, this folder only"
            )
            .accessibilityHint(
                profile.descendantScope == .descendants
                    ? "Turn off to keep this saved layout in this folder only."
                    : "Turn on so subfolders without their own saved choice use this layout."
            )
    }

    @ViewBuilder
    private var subfolderActionButtons: some View {
        Button {
            chooseSubfolderToPreview()
        } label: {
            Label("Preview a subfolder…", systemImage: "eye")
        }
        .disabled(isResolvingTarget)
        .help("Choose a subfolder that uses this layout and preview it")
        .accessibilityHint("Opens a folder chooser, then previews this layout in the selected subfolder.")

        Button {
            chooseSubfolderForBoundary()
        } label: {
            Label("Leave a subfolder alone…", systemImage: "folder.badge.minus")
        }
        .disabled(isResolvingTarget)
        .help("Leave one subfolder and folders inside it unchanged by Rank & Folder")
        .accessibilityHint("Opens a folder chooser and asks for confirmation before changing future layout use.")
    }

    private func scopeUndoLabel(_ change: ScopeUndo) -> some View {
        Label(change.message, systemImage: "checkmark.circle")
            .rankFolderFont(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func scopeUndoButton(_ change: ScopeUndo) -> some View {
        Button("Undo") { undoScopeChange(change) }
            .buttonStyle(.borderless)
            .accessibilityLabel("Undo subfolder layout change")
            .accessibilityHint(change.undoHint)
    }

    private var behaviorIcon: String {
        if !profile.isEnabled { return "pause.fill" }
        if profile.requiresOrganizedView { return "eye.fill" }
        if automation.requiresManualApply(profile) { return "hand.tap.fill" }
        if !automation.setupComplete { return "circle.slash" }
        return "bolt.fill"
    }

    private var behaviorTint: Color {
        if !profile.isEnabled { return Color.secondary }
        if !automation.setupComplete && profile.finderRepresentation != nil {
            return Color.secondary
        }
        return automation.requiresManualApply(profile)
            ? colorVisionMode.color(for: .warning)
            : RankFolderPalette.accent
    }

    private var behaviorTitle: String {
        if !profile.isEnabled { return "Paused. This folder and its subfolders are left alone" }
        if profile.requiresOrganizedView { return "Shown safely in Rank & Folder" }
        if automation.requiresManualApply(profile) { return "Apply manually for this folder" }
        if !automation.setupComplete { return "Finder automation is optional" }
        return "Restore automatically"
    }

    private var behaviorDetail: String {
        if !profile.isEnabled {
            return "Rank & Folder will not use a layout in this folder or its subfolders while this saved choice is paused. Your files and Finder’s current view stay unchanged."
        }
        if profile.requiresOrganizedView {
            return "Rank & Folder reads this folder’s visible names and standard metadata only while a preview is open. It never reads file contents or changes your files."
        }
        if automation.requiresManualApply(profile) {
            return "Finder is not sharing this cloud folder’s location. Use Open in Finder and Apply; automatic matching stays safely off."
        }
        if !automation.setupComplete {
            return "Your layout is saved, and Preview works now. Turn on Finder automation only if you want Rank & Folder to restore this layout inside Finder."
        }
        if profile.descendantScope == .descendants {
            return "When Finder opens this folder or a subfolder without its own saved choice, Rank & Folder restores these sections and order."
        }
        return "When Finder opens this folder, Rank & Folder restores the saved sections and order."
    }

    private var recipeSummary: String {
        var sentences: [String] = []
        for (index, level) in profile.recipe.sections.enumerated() {
            let prefix = index == 0 ? "First, make sections" : "Then make smaller sections"
            sentences.append("\(prefix) by \(level.criterion.displayName.lowercased())\(directionPhrase(level)).")
        }
        let order = profile.recipe.itemOrder.enumerated().map { index, level in
            let label = index == 0 ? level.criterion.displayName : "then \(level.criterion.displayName.lowercased())"
            return "\(label)\(directionPhrase(level))"
        }.joined(separator: ", ")
        if profile.recipe.sections.isEmpty {
            sentences.append("Keep one list and order items by \(order).")
        } else {
            sentences.append("Inside the final section, order items by \(order).")
        }
        return sentences.joined(separator: " ")
    }

    private func directionPhrase(_ level: OrganizationLevel) -> String {
        guard let direction = level.direction else { return "" }
        return " (\(direction.displayName(for: level.criterion).lowercased()))"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.profile(id: profile.id)?.isEnabled ?? false },
            set: {
                store.update(id: profile.id, isEnabled: $0)
                automation.resetStatus()
            }
        )
    }

    private var descendantScopeBinding: Binding<Bool> {
        Binding(
            get: {
                store.profile(id: profile.id)?.descendantScope == .descendants
            },
            set: { includesSubfolders in
                let previous = store.profile(id: profile.id)?.descendantScope
                    ?? .exactFolder
                let next: ProfileDescendantScope = includesSubfolders
                    ? .descendants
                    : .exactFolder
                guard previous != next else { return }
                if store.update(id: profile.id, descendantScope: next) {
                    scopeUndo = ScopeUndo(
                        operation: .restoreScope(previous),
                        message: includesSubfolders
                            ? "This layout now includes subfolders."
                            : "This layout now stays in this folder.",
                        undoHint: includesSubfolders
                            ? "Return to this folder only."
                            : "Include subfolders again."
                    )
                    automation.resetStatus()
                    AccessibilityNotification.Announcement(
                        "\(scopeUndo?.message ?? "Subfolder layout setting changed.") Undo is available."
                    ).post()
                }
            }
        )
    }

    private var boundaryConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingBoundaryURL != nil },
            set: { if !$0 { pendingBoundaryURL = nil } }
        )
    }

    private var boundaryConfirmationTitle: String {
        let name = pendingBoundaryURL?.lastPathComponent ?? "this subfolder"
        return "Leave “\(name)” and its subfolders alone?"
    }

    private var boundaryConfirmationMessage: String {
        let name = pendingBoundaryURL?.lastPathComponent ?? "that subfolder"
        return "Rank & Folder will stop using the layout from \(profile.displayName) in \(name) and folders inside it. This changes future previews and Finder automation; it does not change files or reset the view Finder already shows. A deeper folder can still have its own saved layout."
    }

    private func undoScopeChange(_ change: ScopeUndo) {
        switch change.operation {
        case .restoreScope(let previous):
            guard store.update(
                id: profile.id,
                descendantScope: previous
            ) else { return }
        case .removeBoundary(let boundaryID):
            store.removeBoundary(id: boundaryID)
        }
        scopeUndo = nil
        automation.resetStatus()
        AccessibilityNotification.Announcement(
            "Subfolder layout change undone."
        ).post()
    }

    private func presentOrganizedView(for _: URL) {
        guard !isResolvingTarget else { return }
        isResolvingTarget = true
        Task { @MainActor in
            defer { isResolvingTarget = false }
            guard let layout = await store.exactPreviewResolution(
                profileID: profile.id
            ) else {
                store.lastError = "Rank & Folder could not verify this folder for a preview. If this is an older saved choice, or the folder was moved or replaced, remove its saved layout and add it again."
                return
            }
            SecondaryWindowStore.shared.organizedLayout = layout
            openWindow(id: "organized-view")
        }
    }

    private func chooseSubfolderToPreview() {
        guard let folderURL = chooseSubfolderURL(
            title: "Preview a Subfolder",
            message: "Choose a subfolder that uses the layout from \(profile.displayName).",
            prompt: "Preview"
        ) else { return }

        isResolvingTarget = true
        Task { @MainActor in
            defer { isResolvingTarget = false }
            guard case .resolved(let layout) = await store.resolution(for: folderURL),
                  layout.sourceProfile.id == profile.id,
                  case .inherited = layout.origin else {
                store.lastError = "That folder does not currently use the layout from \(profile.displayName). Choose a subfolder without its own saved choice."
                return
            }
            SecondaryWindowStore.shared.organizedLayout = layout
            openWindow(id: "organized-view")
        }
    }

    private func chooseSubfolderForBoundary() {
        pendingBoundaryURL = chooseSubfolderURL(
            title: "Leave a subfolder alone",
            message: "Choose a subfolder that Rank & Folder should leave alone, along with folders inside it.",
            prompt: "Choose subfolder"
        )
    }

    private func createPendingBoundary() {
        guard let folderURL = pendingBoundaryURL else { return }
        pendingBoundaryURL = nil
        isResolvingTarget = true
        Task { @MainActor in
            defer { isResolvingTarget = false }
            let existingBoundaryIDs = Set(store.boundaries.map(\.id))
            if let boundaryID = await store.addBoundary(
                folderURL: folderURL,
                under: profile.id
            ) {
                if !existingBoundaryIDs.contains(boundaryID) {
                    scopeUndo = ScopeUndo(
                        operation: .removeBoundary(boundaryID),
                        message: "\(folderURL.lastPathComponent) and its subfolders will now be left alone.",
                        undoHint: "Allow the layout from \(profile.displayName) there again."
                    )
                    AccessibilityNotification.Announcement(
                        "\(folderURL.lastPathComponent) and its subfolders will now be left alone. Undo is available."
                    ).post()
                }
                automation.resetStatus()
            }
        }
    }

    private func chooseSubfolderURL(
        title: String,
        message: String,
        prompt: String
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = profile.folderURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func updateSection(at index: Int, to level: OrganizationLevel) {
        updateRecipe { recipe in
            guard recipe.sections.indices.contains(index) else { return }
            recipe.sections[index] = level
        }
    }

    private func addSection() {
        updateRecipe { recipe in
            guard recipe.sections.count < OrganizationRecipe.maximumLevelsPerArea else { return }
            recipe.sections.append(OrganizationLevel(criterion: unusedCriterion(in: recipe.sections)))
        }
    }

    private func moveSection(from index: Int, by offset: Int) {
        updateRecipe { recipe in move(&recipe.sections, from: index, by: offset) }
    }

    private func removeSection(at index: Int) {
        updateRecipe { recipe in
            guard recipe.sections.indices.contains(index) else { return }
            recipe.sections.remove(at: index)
        }
    }

    private func updateItemOrder(at index: Int, to level: OrganizationLevel) {
        updateRecipe { recipe in
            guard recipe.itemOrder.indices.contains(index) else { return }
            recipe.itemOrder[index] = level
        }
    }

    private func addItemOrder() {
        updateRecipe { recipe in
            guard recipe.itemOrder.count < OrganizationRecipe.maximumLevelsPerArea else { return }
            recipe.itemOrder.append(OrganizationLevel(criterion: unusedCriterion(in: recipe.itemOrder)))
        }
    }

    private func moveItemOrder(from index: Int, by offset: Int) {
        updateRecipe { recipe in move(&recipe.itemOrder, from: index, by: offset) }
    }

    private func removeItemOrder(at index: Int) {
        updateRecipe { recipe in
            guard recipe.itemOrder.count > 1, recipe.itemOrder.indices.contains(index) else { return }
            recipe.itemOrder.remove(at: index)
        }
    }

    private func updateRecipe(_ change: (inout OrganizationRecipe) -> Void) {
        guard var recipe = store.profile(id: profile.id)?.recipe else { return }
        change(&recipe)
        store.update(id: profile.id, recipe: recipe)
        automation.resetStatus()
    }

    private func unusedCriterion(in levels: [OrganizationLevel]) -> AdvancedCriterion {
        let used = Set(levels.map(\.criterion))
        return AdvancedCriterion.allCases.first { !used.contains($0) } ?? .name
    }

    private func move(_ levels: inout [OrganizationLevel], from index: Int, by offset: Int) {
        let destination = index + offset
        guard levels.indices.contains(index), levels.indices.contains(destination) else { return }
        levels.swapAt(index, destination)
    }
}

/// The two panels below the layout editor, shown one at a time.
private enum ProfileEditorPanel: String, CaseIterable, Identifiable {
    case subfolders
    case finder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subfolders: "Subfolders"
        case .finder: "Finder automation"
        }
    }

    var systemImage: String {
        switch self {
        case .subfolders: "folder.badge.plus"
        case .finder: "finder"
        }
    }
}

/// The three steps of building a layout. Sections split the folder into
/// headings, item order decides what comes first inside the smallest section,
/// and preview shows the result without touching Finder.
private enum LayoutEditorStage: String, CaseIterable, Identifiable {
    case sections
    case itemOrder
    case preview

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .sections: "Sections"
        case .itemOrder: "Item order"
        case .preview: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .sections: "rectangle.split.3x1"
        case .itemOrder: "arrow.up.arrow.down"
        case .preview: "eye"
        }
    }
}

/// A numbered heading for one step of the editor, with a short line saying what
/// the step is for.
private struct WorkflowStepHeader: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .rankFolderFont(.headline, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(RankFolderPalette.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).rankFolderFont(.title2, weight: .semibold)
                Text(detail).rankFolderFont(.body).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}

/// A small read-only preview of how a folder would look under a recipe. It
/// reads folder metadata only and never opens or changes a file.
struct CompactFolderPreview: View {
    let profile: RankFolderProfile
    let recipe: OrganizationRecipe?
    let heading: String
    @State private var items: [AdvancedFolderItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        profile: RankFolderProfile,
        recipe: OrganizationRecipe? = nil,
        heading: String = "Live folder preview"
    ) {
        self.profile = profile
        self.recipe = recipe
        self.heading = heading
    }

    private var previewRules: [AdvancedViewRule] {
        let selectedRecipe = recipe ?? profile.recipe
        return selectedRecipe.sections.map {
            AdvancedViewRule(
                id: $0.id,
                behavior: .group,
                criterion: $0.criterion,
                direction: $0.direction ?? .ascending
            )
        } + selectedRecipe.itemOrder.map {
            AdvancedViewRule(
                id: $0.id,
                behavior: .sort,
                criterion: $0.criterion,
                direction: $0.direction ?? .ascending
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(RankFolderPalette.action.opacity(0.12))
                    Image(systemName: "macwindow")
                        .foregroundStyle(RankFolderPalette.action)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(heading).rankFolderFont(.title3, weight: .semibold)
                    Text("Every visible item, placed into the current grouping structure")
                        .rankFolderFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Preview", systemImage: "eye")
                    .rankFolderFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            finderWindow

            Text("The preview uses the access already granted for this folder. It does not record the screen or ask for Full Disk Access.")
                .rankFolderFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .task(id: profile.folderPath) { await load() }
    }

    private var finderWindow: some View {
        FinderColumnPreview(
            folderName: profile.displayName,
            items: items,
            rules: previewRules,
            isLoading: isLoading,
            errorMessage: errorMessage
        )
        .frame(maxHeight: 440)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        guard let bookmarkData = profile.folderBookmarkData,
              let resourceIdentifier = profile.folderResourceIdentifier,
              let volumeIdentifier = RankFolderProfile.archivedVolumeIdentifier(for: profile.folderURL) else {
            isLoading = false
            errorMessage = "Folder access needs to be refreshed. Remove this saved folder and add it again."
            return
        }
        let identity = ResolvedFolderIdentity(
            canonicalURL: profile.folderURL,
            bookmarkData: bookmarkData,
            resourceIdentifier: resourceIdentifier,
            volumeIdentifier: volumeIdentifier,
            providerLocation: .unknown
        )
        let resolution = ResolvedFolderLayout(
            targetFolderURL: profile.folderURL,
            targetIdentity: identity,
            sourceProfile: profile,
            origin: .exact
        )
        do {
            items = try await Task.detached(priority: .userInitiated) {
                try AdvancedFolderLoader.load(resolution: resolution)
            }.value
        } catch {
            items = []
            errorMessage = "Rank & Folder could not read this folder’s visible names and metadata."
        }
        isLoading = false
    }
}

/// One reversible change to how far a layout reaches, held so the person can
/// undo it from the message that reports it.
private struct ScopeUndo {
    enum Operation {
        case restoreScope(ProfileDescendantScope)
        case removeBoundary(UUID)
    }

    let operation: Operation
    let message: String
    let undoHint: String
}

/// The editable list of levels for one half of a recipe. Sections and item
/// order both use it, which is why the labels are passed in.
private struct RecipeArea: View {
    let emptyText: String
    let addTitle: String
    let rowNoun: String
    let levels: [OrganizationLevel]
    let canBeEmpty: Bool
    let update: (Int, OrganizationLevel) -> Void
    let add: () -> Void
    let move: (Int, Int) -> Void
    let remove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if levels.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle")
                    Text(emptyText)
                }
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 11))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                        OrganizationLevelRow(
                            number: index + 1,
                            label: rowNoun,
                            level: level,
                            canMoveUp: index > 0,
                            canMoveDown: index < levels.count - 1,
                            canRemove: canBeEmpty || levels.count > 1,
                            update: { update(index, $0) },
                            moveUp: { move(index, -1) },
                            moveDown: { move(index, 1) },
                            remove: { remove(index) }
                        )
                    }
                }
            }

            HStack {
                Text(levels.isEmpty ? "Optional" : "\(levels.count) of \(OrganizationRecipe.maximumLevelsPerArea) levels")
                    .rankFolderFont(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: add) {
                    Label(addTitle, systemImage: "plus.circle.fill")
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(levels.count >= OrganizationRecipe.maximumLevelsPerArea)
            }
        }
    }
}

/// One level in a recipe, with its criterion, its direction, and the controls
/// that move or remove it.
private struct OrganizationLevelRow: View {
    let number: Int
    let label: String
    let level: OrganizationLevel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canRemove: Bool
    let update: (OrganizationLevel) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .rankFolderFont(.callout, weight: .bold)
                    .foregroundStyle(RankFolderPalette.accent)
                    .frame(width: 25, height: 25)
                    .background(RankFolderPalette.accent.opacity(0.12), in: Circle())
                Text("\(label) \(number)")
                    .rankFolderFont(.headline, weight: .semibold)
                Spacer()
                ControlGroup {
                    Button(action: moveUp) { Image(systemName: "chevron.up") }
                        .disabled(!canMoveUp)
                        .help("Move up")
                        .accessibilityLabel("Move \(level.criterion.displayName) up")
                    Button(action: moveDown) { Image(systemName: "chevron.down") }
                        .disabled(!canMoveDown)
                        .help("Move down")
                        .accessibilityLabel("Move \(level.criterion.displayName) down")
                    Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                        .disabled(!canRemove)
                        .help("Remove this rule")
                        .accessibilityLabel("Remove \(level.criterion.displayName) rule")
                }
                .controlGroupStyle(.navigation)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) { rulePickers }
                VStack(alignment: .leading, spacing: 10) { rulePickers }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [RankFolderPalette.accent.opacity(0.055), Color(nsColor: .controlBackgroundColor)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label) \(number), \(level.criterion.displayName)")
    }

    @ViewBuilder
    private var rulePickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Organize by")
                .rankFolderFont(.callout)
                .foregroundStyle(.secondary)
            Picker("Organize by", selection: criterionBinding) {
                ForEach(AdvancedCriterion.allCases) { criterion in
                    Text(criterion.displayName).tag(criterion)
                }
            }
            .labelsHidden()
            .frame(minWidth: 175)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Direction")
                .rankFolderFont(.callout)
                .foregroundStyle(.secondary)
            Picker("Direction", selection: directionBinding) {
                Text("Keep Finder’s current direction").tag(DirectionChoice.standard)
                Text(AdvancedSortDirection.ascending.displayName(for: level.criterion))
                    .tag(DirectionChoice.ascending)
                Text(AdvancedSortDirection.descending.displayName(for: level.criterion))
                    .tag(DirectionChoice.descending)
            }
            .labelsHidden()
            .frame(minWidth: 205)
        }
    }

    private var criterionBinding: Binding<AdvancedCriterion> {
        Binding(
            get: { level.criterion },
            set: {
                var changed = level
                changed.criterion = $0
                update(changed)
            }
        )
    }

    private var directionBinding: Binding<DirectionChoice> {
        Binding(
            get: { DirectionChoice(level.direction) },
            set: {
                var changed = level
                changed.direction = $0.value
                update(changed)
            }
        )
    }
}

/// The direction shown for one level. Standard means the criterion decides its
/// own direction rather than the person choosing one.
private enum DirectionChoice: String, Hashable {
    case standard
    case ascending
    case descending

    init(_ direction: AdvancedSortDirection?) {
        switch direction {
        case nil: self = .standard
        case .ascending: self = .ascending
        case .descending: self = .descending
        }
    }

    var value: AdvancedSortDirection? {
        switch self {
        case .standard: nil
        case .ascending: .ascending
        case .descending: .descending
        }
    }
}
