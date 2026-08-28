import AppKit
import Combine
import SwiftUI

/// Whether the app follows the Mac's appearance or is held to light or dark.
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

/// What a status color is saying, rather than which color it is. The color for
/// each role is decided by the current color vision mode.
enum StatusColorRole {
    case information
    case success
    case warning
    case danger
}

/// The text size the app draws at. Larger is the starting value.
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

/// Carries the chosen text size down the view tree as a multiplier.
private struct RankFolderTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

/// Carries a padding multiplier down the view tree so panels can be tightened in
/// one place.
private struct RankFolderPanelSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

/// Makes the text scale and the panel spacing readable from any view.
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

/// The named text sizes the app draws with, each with a fixed point size that
/// the chosen text size then scales.
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

/// Applies a font role at the current text scale.
private struct RankFolderFontModifier: ViewModifier {
    @Environment(\.rankFolderTextScale) private var scale
    let role: RankFolderFontRole
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: role.pointSize * scale, weight: weight, design: design))
    }
}

/// Applies one of the named font roles at the current text scale.
extension View {
    func rankFolderFont(
        _ role: RankFolderFontRole,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(RankFolderFontModifier(role: role, weight: weight, design: design))
    }
}

/// The color vision mode the whole interface renders in. It decides both the
/// status colors and the fills, so choosing one repaints the app rather than
/// only its status indicators.
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

    /// Status colors come from the same set the rest of the interface fills
    /// with, so a status color and a filled button never disagree about what a
    /// mode looks like.
    ///
    /// Each set was checked two ways. Every color clears 4.5 to 1 against a
    /// white background, and every pair was run through a dichromacy simulation
    /// for the deficiency the set is meant for. The red-green set separates on
    /// every pair. Under tritanopia, warning and danger both fall in the warm
    /// range and separate by lightness rather than by hue, which is why every
    /// place that shows a status also shows a symbol and a word. The complete
    /// deficiency set carries no hue at all and leaves the whole job to those.
    func color(for role: StatusColorRole) -> Color {
        switch (self, role) {
        case (.standard, .information): Color(red: 0.03, green: 0.43, blue: 0.38)
        case (.standard, .success): Color(red: 0.10, green: 0.45, blue: 0.16)
        case (.standard, .warning): Color(red: 0.60, green: 0.39, blue: 0.02)
        case (.standard, .danger): Color(red: 0.79, green: 0.24, blue: 0.28)

        case (.redGreen, .information): Color(red: 0.09, green: 0.36, blue: 0.68)
        case (.redGreen, .success): Color(red: 0.10, green: 0.13, blue: 0.31)
        case (.redGreen, .warning): Color(red: 0.63, green: 0.42, blue: 0.02)
        case (.redGreen, .danger): Color(red: 0.42, green: 0.15, blue: 0.04)

        case (.blueYellow, .information): Color(red: 0.33, green: 0.10, blue: 0.24)
        case (.blueYellow, .success): Color(red: 0.02, green: 0.42, blue: 0.36)
        case (.blueYellow, .warning): Color(red: 0.45, green: 0.30, blue: 0.00)
        case (.blueYellow, .danger): Color(red: 0.75, green: 0.13, blue: 0.28)

        case (.monochrome, _): Color.primary
        }
    }

    /// The label color for text or a symbol placed on top of a solid status
    /// fill. The hued sets are all dark enough for white. The complete
    /// deficiency set fills with the primary label color, which is dark in light
    /// appearance and light in dark appearance, so a fixed white label would
    /// disappear against it in dark appearance. The text background color is the
    /// inverse of the primary label color in both appearances.
    var labelOnStatusFill: Color {
        self == .monochrome ? Color(nsColor: .textBackgroundColor) : .white
    }
}

/// Carries the chosen color vision mode down the view tree.
private struct ColorVisionModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ColorVisionMode.standard
}

/// Makes the color vision mode readable from any view.
extension EnvironmentValues {
    var rankFolderColorVisionMode: ColorVisionMode {
        get { self[ColorVisionModeEnvironmentKey.self] }
        set { self[ColorVisionModeEnvironmentKey.self] = newValue }
    }
}

@MainActor
/// The three appearance choices and their storage. Each choice writes itself
/// back to user defaults as it changes, so nothing has to be saved explicitly.
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
        didSet {
            defaults.set(colorVisionMode.rawValue, forKey: Key.colorVision)
            RankFolderPalette.use(colorVisionMode)
        }
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
        RankFolderPalette.use(colorVisionMode)
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

/// The Appearance tab of Settings, holding the appearance, text size, and color
/// vision choices with a live preview of the colors each mode produces.
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

/// The Settings window and its tabs.
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

/// The Reset tab of Settings, which only opens the separate review window rather
/// than resetting anything itself.
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

/// The reset review window. It gathers the choices first and then shows exactly
/// what will happen before anything is removed.
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

/// One optional item the person can include in a reset.
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

/// One line of the final reset summary, listing something that will or will not
/// change.
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

/// Shows what the selected color vision mode looks like, so the choice can be
/// read from the colors themselves rather than only from its name.
private struct StatusPalettePreview: View {
    let mode: ColorVisionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                status("Ready", image: "checkmark.circle.fill", role: .success)
                status("Needs attention", image: "exclamationmark.triangle.fill", role: .warning)
                status("Error", image: "xmark.circle.fill", role: .danger)
            }
            HStack(spacing: 10) {
                fill("Buttons", color: RankFolderPalette.tokens(for: mode).action)
                fill("Model", color: RankFolderPalette.tokens(for: mode).plum)
                fill("Highlights", color: RankFolderPalette.tokens(for: mode).coral)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color preview for the selected mode")
    }

    /// Shows a filled sample rather than a tinted one, because the fills are
    /// what a person sees most and are where a label has to stay readable.
    private func fill(_ title: String, color: Color) -> some View {
        Text(title)
            .rankFolderFont(.caption, weight: .semibold)
            .foregroundStyle(mode.labelOnStatusFill)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color, in: Capsule())
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
