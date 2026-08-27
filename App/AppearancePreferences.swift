import AppKit
import Combine
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum StatusColorRole {
    case information
    case success
    case warning
    case danger
}

enum AppTextSize: String, CaseIterable, Identifiable {
    case standard
    case larger
    case largest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }

    var textScale: CGFloat {
        switch self {
        case .standard: 1.0
        case .larger: 1.10
        case .largest: 1.22
        }
    }
}

private struct RankFolderTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct RankFolderPanelSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var rankFolderTextScale: CGFloat {
        get { self[RankFolderTextScaleKey.self] }
        set { self[RankFolderTextScaleKey.self] = newValue }
    }

    var rankFolderPanelSpacing: CGFloat {
        get { self[RankFolderPanelSpacingKey.self] }
        set { self[RankFolderPanelSpacingKey.self] = newValue }
    }
}

enum RankFolderFontRole {
    case caption2, caption, callout, body, headline, title3, title2, title, largeTitle

    var pointSize: CGFloat {
        switch self {
        case .caption2: 10
        case .caption: 12
        case .callout: 13
        case .body: 14
        case .headline: 14
        case .title3: 17
        case .title2: 20
        case .title: 25
        case .largeTitle: 32
        }
    }
}

private struct RankFolderFontModifier: ViewModifier {
    @Environment(\.rankFolderTextScale) private var scale
    let role: RankFolderFontRole
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: role.pointSize * scale, weight: weight, design: design))
    }
}

extension View {
    func rankFolderFont(
        _ role: RankFolderFontRole,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(RankFolderFontModifier(role: role, weight: weight, design: design))
    }
}

enum ColorVisionMode: String, CaseIterable, Identifiable {
    case standard
    case redGreen
    case blueYellow
    case monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard colors"
        case .redGreen: "Red-green color vision deficiency"
        case .blueYellow: "Blue-yellow color vision deficiency"
        case .monochrome: "Complete color vision deficiency"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            "Uses familiar macOS status colors."
        case .redGreen:
            "Designed for deuteranomaly, protanomaly, deuteranopia, and protanopia."
        case .blueYellow:
            "Designed for tritanomaly and tritanopia."
        case .monochrome:
            "Uses words and symbols without relying on hue. Designed for monochromacy and achromatopsia."
        }
    }

    func color(for role: StatusColorRole) -> Color {
        switch (self, role) {
        case (.standard, .information): RankFolderPalette.accent
        case (.standard, .success): .green
        case (.standard, .warning): .orange
        case (.standard, .danger): .red

        case (.redGreen, .information): .cyan
        case (.redGreen, .success): .blue
        case (.redGreen, .warning): .orange
        case (.redGreen, .danger): .purple

        case (.blueYellow, .information): .purple
        case (.blueYellow, .success): .green
        case (.blueYellow, .warning): .pink
        case (.blueYellow, .danger): .red

        case (.monochrome, .information): .primary
        case (.monochrome, .success): .primary
        case (.monochrome, .warning): .primary
        case (.monochrome, .danger): .primary
        }
    }
}

private struct ColorVisionModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ColorVisionMode.standard
}

extension EnvironmentValues {
    var rankFolderColorVisionMode: ColorVisionMode {
        get { self[ColorVisionModeEnvironmentKey.self] }
        set { self[ColorVisionModeEnvironmentKey.self] = newValue }
    }
}

@MainActor
final class AppearancePreferences: ObservableObject {
    private enum Key {
        static let appearance = "appearance.mode"
        static let colorVision = "appearance.colorVision"
        static let textSize = "appearance.textSize"
        static let legacyPanelSpacing = "appearance.panelSpacing"
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Key.appearance)
            applyAppearanceToEveryWindow()
        }
    }

    @Published var colorVisionMode: ColorVisionMode {
        didSet { defaults.set(colorVisionMode.rawValue, forKey: Key.colorVision) }
    }

    @Published var textSize: AppTextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Key.textSize) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearanceMode = AppAppearanceMode(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
        self.colorVisionMode = ColorVisionMode(
            rawValue: defaults.string(forKey: Key.colorVision) ?? ""
        ) ?? .standard
        self.textSize = AppTextSize(
            rawValue: defaults.string(forKey: Key.textSize) ?? ""
        ) ?? .larger
        defaults.removeObject(forKey: Key.legacyPanelSpacing)
        applyAppearanceToEveryWindow()
    }

    func resetToDefaults() {
        appearanceMode = .system
        colorVisionMode = .standard
        textSize = .larger
        defaults.removeObject(forKey: Key.legacyPanelSpacing)
    }

    /// AppKit owns window appearance on macOS. Applying the choice at that
    /// level keeps sheets, settings, and separately opened windows in sync and
    /// avoids stale SwiftUI materials when a forced theme returns to System.
    private func applyAppearanceToEveryWindow() {
        let selectedAppearance = appearanceMode.appKitAppearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            NSApp.appearance = selectedAppearance
            for window in NSApp.windows {
                window.appearance = selectedAppearance
                window.contentView?.needsLayout = true
                window.contentView?.needsDisplay = true
                window.invalidateShadow()
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var preferences: AppearancePreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Appearance", systemImage: "paintpalette.fill")
                        .rankFolderFont(.largeTitle, weight: .semibold)
                    Text("Choose how Rank & Folder looks without changing Finder or the rest of your Mac.")
                        .foregroundStyle(.secondary)
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Appearance").rankFolderFont(.title2, weight: .semibold)
                        Picker("Appearance", selection: $preferences.appearanceMode) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Label(mode.displayName, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("System follows your Mac automatically.")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Text size").rankFolderFont(.title2, weight: .semibold)
                            Text("Rank & Folder starts with Larger text. Choose the size that is easiest for you to read.")
                                .rankFolderFont(.body)
                                .foregroundStyle(.secondary)
                        }
                        Picker("Text size", selection: $preferences.textSize) {
                            ForEach(AppTextSize.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Color vision support").rankFolderFont(.title2, weight: .semibold)
                            Text("Color is always reinforced with a word and a distinct symbol.")
                                .rankFolderFont(.body)
                                .foregroundStyle(.secondary)
                        }

                        Picker("Color vision support", selection: $preferences.colorVisionMode) {
                            ForEach(ColorVisionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        Text(preferences.colorVisionMode.detail)
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)

                        StatusPalettePreview(mode: preferences.colorVisionMode)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.rankFolderColorVisionMode, preferences.colorVisionMode)
        .environment(\.rankFolderTextScale, preferences.textSize.textScale)
        .environment(\.rankFolderPanelSpacing, 1)
        .textSelection(.enabled)
    }
}

struct RankFolderSettingsView: View {
    @ObservedObject var appearance: AppearancePreferences
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var store: ProfileStore
    @ObservedObject var automation: AutomationCoordinator

    var body: some View {
        TabView {
            AppearanceSettingsView(preferences: appearance)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            GeneralSettingsView(
                appearance: appearance,
                onboarding: onboarding,
                store: store,
                automation: automation
            )
            .tabItem { Label("Reset", systemImage: "arrow.counterclockwise.circle") }

        }
        .environment(\.rankFolderColorVisionMode, appearance.colorVisionMode)
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appearance: AppearancePreferences
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var store: ProfileStore
    @ObservedObject var automation: AutomationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Reset Rank & Folder", systemImage: "arrow.counterclockwise.circle.fill")
                        .rankFolderFont(.largeTitle, weight: .semibold)
                    Text("Return Rank & Folder to a fresh-start state. You will review every item before anything is reset.")
                        .foregroundStyle(.secondary)
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start over").rankFolderFont(.title2, weight: .semibold)
                        Text("This opens a separate review window. Your folders and files are never deleted or changed.")
                            .rankFolderFont(.body)
                            .foregroundStyle(.secondary)

                        Button("Review reset options…", role: .destructive) {
                            openWindow(id: "reset")
                        }
                        .controlSize(.large)
                    }
                }

                Label(
                    "Reset never deletes, moves, renames, or opens your files.",
                    systemImage: "hand.raised.fill"
                )
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

struct ResetAppDataView: View {
    private enum Stage { case choices, review }

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.rankFolderPanelSpacing) private var panelSpacing
    @ObservedObject var appearance: AppearancePreferences
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var store: ProfileStore
    @ObservedObject var automation: AutomationCoordinator
    @StateObject private var runtime = ManagedOllamaRuntime.shared
    @State private var stage = Stage.choices
    @State private var removeOllamaProgram = false
    @State private var removeAllModels = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20 * panelSpacing) {
                    resetHeading
                    if stage == .choices { resetChoices } else { resetReview }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(28 * panelSpacing)
                .frame(maxWidth: .infinity)
            }

            Divider()
            footer
                .padding(18 * panelSpacing)
                .background(.regularMaterial)
        }
        .background(RankFolderBackdrop())
        .onAppear {
            stage = .choices
            removeOllamaProgram = false
            removeAllModels = false
        }
        .onDisappear {
            stage = .choices
            removeOllamaProgram = false
            removeAllModels = false
        }
    }

    private var resetHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                stage == .choices ? "Choose what to reset" : "Are you sure?",
                systemImage: stage == .choices
                    ? "checklist"
                    : "exclamationmark.arrow.triangle.2.circlepath"
            )
            .rankFolderFont(.largeTitle, weight: .semibold)
            Text(stage == .choices
                ? "Rank & Folder’s own settings reset automatically. Removing local-model downloads is optional."
                : "Review the complete list below. Nothing happens until you choose the red reset button.")
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var resetChoices: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rank & Folder will always reset")
                        .rankFolderFont(.title2, weight: .semibold)
                    ResetReviewRow(icon: "folder.badge.minus", title: savedLayoutSummary, detail: "Only saved layout choices are removed. The folders stay where they are.")
                    ResetReviewRow(icon: "paintpalette", title: "Appearance and text choices", detail: "Returns appearance, text size, and color vision support to their defaults.")
                    ResetReviewRow(icon: "cpu", title: "Model setup choices", detail: "Forgets the selected model and Mac compatibility consent, but keeps downloads unless selected below.")
                    ResetReviewRow(icon: "rectangle.on.rectangle", title: "Quick tour progress", detail: "The tour opens again at its first page.")
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Optional downloads to remove")
                        .rankFolderFont(.title2, weight: .semibold)
                    ResetChoiceToggle(
                        isOn: $removeOllamaProgram,
                        icon: "shippingbox",
                        title: "Remove Rank & Folder’s Ollama program",
                        detail: "Deletes only the Ollama runner kept inside Rank & Folder. A separate Ollama Desktop app is not touched."
                    )
                    Divider()
                    ResetChoiceToggle(
                        isOn: $removeAllModels,
                        icon: "externaldrive.badge.minus",
                        title: "Remove all Rank & Folder-managed models",
                        detail: "Deletes model files in Rank & Folder’s private model folder. Models in a separate Ollama library are not touched."
                    )
                }
            }
        }
    }

    private var resetReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Will be reset")
                        .rankFolderFont(.title2, weight: .semibold)
                    ResetReviewRow(icon: "checkmark.circle.fill", title: savedLayoutSummary, detail: "Folders and their contents remain unchanged.")
                    ResetReviewRow(icon: "checkmark.circle.fill", title: "Appearance, model choices, and pending Finder tasks", detail: "These return to their fresh-install defaults.")
                    ResetReviewRow(icon: "checkmark.circle.fill", title: "Quick tour", detail: "Reopens at step 1.")
                    if removeOllamaProgram {
                        ResetReviewRow(icon: "checkmark.circle.fill", title: "Rank & Folder’s Ollama program", detail: "The private runner is removed.")
                    }
                    if removeAllModels {
                        ResetReviewRow(icon: "checkmark.circle.fill", title: "All Rank & Folder-managed models", detail: "The private model folder is removed.")
                    }
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Will not be changed")
                        .rankFolderFont(.title2, weight: .semibold)
                    ResetReviewRow(icon: "hand.raised.fill", title: "Your files and folders", detail: "Nothing is moved, renamed, opened, or deleted.")
                    ResetReviewRow(icon: "lock.shield", title: "macOS permissions and Finder’s current view", detail: "Accessibility and other System Settings choices remain under your control.")
                    ResetReviewRow(icon: "desktopcomputer", title: "Separate Ollama installations", detail: "Ollama Desktop and its external model library are left alone.")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(stage == .choices ? "Cancel" : "Back") {
                if stage == .choices {
                    dismissWindow(id: "reset")
                } else {
                    stage = .choices
                }
            }
            .id(stage == .choices ? "cancel-reset" : "back-reset")
            Spacer()
            if stage == .choices {
                Button("Review reset") { stage = .review }
                    .buttonStyle(RankFolderPrimaryActionButtonStyle())
            } else {
                Button(finalButtonTitle, role: .destructive, action: performReset)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
            }
        }
    }

    private var savedLayoutSummary: String {
        let layouts = store.profiles.count
        let boundaries = store.boundaries.count
        return "\(layouts) saved \(layouts == 1 ? "layout" : "layouts") and \(boundaries) leave-alone \(boundaries == 1 ? "choice" : "choices")"
    }

    private var finalButtonTitle: String {
        removeOllamaProgram || removeAllModels
            ? "Reset and remove selected downloads"
            : "Reset Rank & Folder"
    }

    private func performReset() {
        let shouldRemoveOllamaProgram = removeOllamaProgram
        let shouldRemoveAllModels = removeAllModels
        stage = .choices
        removeOllamaProgram = false
        removeAllModels = false
        dismissWindow(id: "models")
        dismissWindow(id: "download-review")
        dismissWindow(id: "help")
        dismissWindow(id: "settings")
        dismissWindow(id: "reset")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            await runtime.removeManagedFiles(
                removeRuntime: shouldRemoveOllamaProgram,
                removeModels: shouldRemoveAllModels
            )
            store.resetAllSavedChoices()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                appearance.resetToDefaults()
                automation.resetForAppReset()
                onboarding.resetToDefaultsAndShowTour()
            }
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "profiles")
            openWindow(id: "tour")
            AccessibilityNotification.Announcement(
                "Rank & Folder was reset. The quick tour is open at step 1. No files were changed."
            ).post()
        }
    }
}

private struct ResetChoiceToggle: View {
    @Binding var isOn: Bool
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .rankFolderFont(.title3)
                    .foregroundStyle(RankFolderPalette.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).rankFolderFont(.body, weight: .semibold)
                    Text(detail).rankFolderFont(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }
}

private struct ResetReviewRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .rankFolderFont(.title3)
                .foregroundStyle(RankFolderPalette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).rankFolderFont(.body, weight: .semibold)
                Text(detail).rankFolderFont(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusPalettePreview: View {
    let mode: ColorVisionMode

    var body: some View {
        HStack(spacing: 10) {
            status("Ready", image: "checkmark.circle.fill", role: .success)
            status("Needs attention", image: "exclamationmark.triangle.fill", role: .warning)
            status("Error", image: "xmark.circle.fill", role: .danger)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status color preview")
    }

    private func status(_ title: String, image: String, role: StatusColorRole) -> some View {
        let tint = mode.color(for: role)
        return Label(title, systemImage: image)
            .rankFolderFont(.caption, weight: .medium)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay { Capsule().stroke(tint.opacity(0.25), lineWidth: 1) }
    }
}
