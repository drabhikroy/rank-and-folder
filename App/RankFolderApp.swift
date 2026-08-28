import AppKit
import SwiftUI

@main
/// The application and its windows. Each window applies the same presentation so
/// appearance, text size, and color vision choices reach all of them.
struct RankFolderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearance = AppearancePreferences()
    @StateObject private var onboarding = OnboardingStore()
    private let services = AppServices.shared

    var body: some Scene {
        Window("Rank & Folder", id: "profiles") {
            ContentView(
                store: services.profileStore,
                automation: services.automation
            )
            .environmentObject(onboarding)
            .rankFolderPresentation(appearance)
            .rankFolderWindow(minSize: NSSize(width: 760, height: 520))
        }
        .defaultSize(width: 1040, height: 720)
        .commands { RankFolderCommands(onboarding: onboarding) }

        Window("About Rank & Folder", id: "about") {
            RankFolderAboutView()
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 460, height: 620))
        }
        // Tall enough to clear the whole About panel with a margin below the
        // copyright line, so the window never opens already scrolled.
        .defaultSize(width: 520, height: 760)

        Window("Rank & Folder help", id: "help") {
            RankFolderHelpView()
                .environmentObject(onboarding)
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 560, height: 420))
        }
        .defaultSize(width: 920, height: 680)

        Window("Models", id: "models") {
            ModelCenterView(onboarding: onboarding, store: services.profileStore)
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 620, height: 460))
        }
        .defaultSize(width: 900, height: 720)

        Window("Compare models", id: "model-comparison") {
            ModelComparisonView(onboarding: onboarding)
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 700, height: 500))
        }
        .defaultSize(width: 1080, height: 720)

        Window("Quick tour", id: "tour") {
            WalkthroughView(
                onboarding: onboarding,
                store: services.profileStore,
                selectProfile: { profileID in
                    NotificationCenter.default.post(
                        name: .rankFolderSelectProfile,
                        object: profileID
                    )
                }
            )
            .rankFolderPresentation(appearance)
            .rankFolderWindow(minSize: NSSize(width: 540, height: 420))
            .onDisappear { onboarding.dismissWalkthrough() }
        }
        .defaultSize(width: 820, height: 690)

        Window("Folder preview", id: "organized-view") {
            OrganizedViewWindow()
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 560, height: 400))
        }
        .defaultSize(width: 920, height: 680)

        Window("Model layout", id: "model-layout") {
            ModelLayoutWindow(store: services.profileStore)
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 680, height: 480))
        }
        .defaultSize(width: 840, height: 720)

        Window("Review download", id: "download-review") {
            LocalDownloadReviewView()
                .rankFolderPresentation(appearance)
                .rankFolderWindow(minSize: NSSize(width: 500, height: 400))
        }
        .defaultSize(width: 640, height: 540)

        MenuBarExtra("Rank & Folder", systemImage: "folder.badge.gearshape") {
            RankFolderMenu(automation: services.automation)
                .environmentObject(onboarding)
                .rankFolderPresentation(appearance)
        }

        Window("Settings", id: "settings") {
            RankFolderSettingsView(
                appearance: appearance,
                onboarding: onboarding,
                store: services.profileStore,
                automation: services.automation
            )
            .rankFolderPresentation(appearance)
            .rankFolderWindow(minSize: NSSize(width: 520, height: 480))
        }
        .defaultSize(width: 700, height: 720)

        Window("Reset Rank & Folder", id: "reset") {
            ResetAppDataView(
                appearance: appearance,
                onboarding: onboarding,
                store: services.profileStore,
                automation: services.automation
            )
            .rankFolderPresentation(appearance)
            .rankFolderWindow(minSize: NSSize(width: 560, height: 480))
        }
        .defaultSize(width: 720, height: 700)
    }
}

/// Applies the three appearance choices to a window's content.
private struct RankFolderPresentationModifier: ViewModifier {
    @ObservedObject var appearance: AppearancePreferences

    func body(content: Content) -> some View {
        content
            .environment(\.rankFolderColorVisionMode, appearance.colorVisionMode)
            .environment(\.rankFolderTextScale, appearance.textSize.textScale)
            .environment(\.rankFolderPanelSpacing, 1)
            .tint(RankFolderPalette.action)
            .textSelection(.enabled)
            // Most call sites read the palette as a type property rather than
            // from the environment, so changing the environment value alone
            // leaves them holding the colors of the previous mode. Tying the
            // window content to the mode rebuilds it, which is what makes a new
            // choice visible everywhere at once. The rebuild resets view state
            // such as the selected sidebar row, which is acceptable for a choice
            // made once in Settings.
            .id(appearance.colorVisionMode)
    }
}

/// Sets the parts of window behavior SwiftUI does not expose, such as the
/// minimum content size and whether the zoom button works.
private struct RankFolderWindowConfiguration: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(containing: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(containing: nsView)
    }

    private func configureWindow(containing view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.isMovable = true
            window.isMovableByWindowBackground = false
            window.contentMinSize = minSize
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }
}

/// Shorthands for the two modifiers every window applies.
private extension View {
    func rankFolderPresentation(_ appearance: AppearancePreferences) -> some View {
        modifier(RankFolderPresentationModifier(appearance: appearance))
    }

    func rankFolderWindow(minSize: NSSize) -> some View {
        background(RankFolderWindowConfiguration(minSize: minSize))
    }
}

/// The full preview window, which shows a placeholder until a folder is chosen.
private struct OrganizedViewWindow: View {
    @ObservedObject private var presentation = SecondaryWindowStore.shared

    var body: some View {
        Group {
            if let layout = presentation.organizedLayout {
                AdvancedFolderPreview(resolution: layout)
            } else {
                UtilityWindowPlaceholder(
                    icon: "rectangle.3.group",
                    title: "Choose a folder to preview",
                    detail: "Open a saved folder in Rank & Folder, then choose Preview."
                )
            }
        }
    }
}

/// The local model window, which shows a placeholder until a saved folder is
/// chosen.
private struct ModelLayoutWindow: View {
    @ObservedObject private var presentation = SecondaryWindowStore.shared
    @ObservedObject var store: ProfileStore

    var body: some View {
        Group {
            if let profileID = presentation.modelProfileID,
               let profile = store.profile(id: profileID) {
                SmartSuggestionView(profile: profile, store: store)
            } else {
                UtilityWindowPlaceholder(
                    icon: "cpu",
                    title: "Choose a saved folder",
                    detail: "Open a saved folder, then ask the selected local model for a layout."
                )
            }
        }
    }
}

/// What a secondary window shows before it has anything to show.
private struct UtilityWindowPlaceholder: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(RankFolderPalette.accent)
            Text(title).rankFolderFont(.title2, weight: .semibold)
            Text(detail)
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RankFolderBackdrop())
    }
}

/// The menu bar extra, reporting automation status and offering the actions that
/// do not need the main window.
private struct RankFolderMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    @EnvironmentObject private var onboarding: OnboardingStore
    @ObservedObject var automation: AutomationCoordinator

    var body: some View {
        Label(
            automation.setupComplete ? "Finder automation on" : "Finder automation off (optional)",
            systemImage: automation.setupComplete ? "checkmark.circle.fill" : "circle.slash"
        )
        .foregroundStyle(automation.setupComplete
            ? colorVisionMode.color(for: .success)
            : Color.secondary)
        Text(automation.statusMessage)
            .rankFolderFont(.caption)
        Divider()
        if automation.includesFinderExtension && !automation.finderExtensionEnabled {
            Button("Add Finder menu (optional)…") {
                automation.showFinderExtensionSettings()
            }
        }
        if !automation.accessibilityGranted {
            Button("Turn on Finder automation…") {
                automation.requestAccessibilityPermission()
            }
        }
        if !automation.setupComplete
            || automation.includesFinderExtension && !automation.finderExtensionEnabled {
            Divider()
        }
        Button("Open Rank & Folder") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "profiles")
        }
        Button("Models…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "models")
        }
        Button("Rank & Folder help") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "help")
        }
        Button("Show welcome tour") {
            NSApp.activate(ignoringOtherApps: true)
            onboarding.presentWalkthrough()
            openWindow(id: "tour")
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        Divider()
        Button("Quit Rank & Folder") {
            NSApp.terminate(nil)
        }
    }
}
