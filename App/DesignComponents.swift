import AppKit
import SwiftUI

/// Rank & Folder uses a deep jade action color with warm coral and plum accents.
/// The combination gives the app its own identity while semantic words and
/// symbols continue to carry every important meaning.
///
/// Every value here is a fixed color rather than the system accent. The system
/// accent is chosen in System Settings and can be a light hue such as yellow,
/// which would drop white label text below the WCAG 2.2 AA contrast ratio
/// wherever Rank & Folder fills a control with it. Fixed colors keep the contrast
/// ratios in Docs/Interface-Design.md true on every Mac.
enum RankFolderPalette {
    static let action = Color(red: 0.03, green: 0.43, blue: 0.38)
    static let actionPressed = Color(red: 0.02, green: 0.34, blue: 0.31)
    static let coral = Color(red: 0.79, green: 0.24, blue: 0.28)
    static let plum = Color(red: 0.39, green: 0.20, blue: 0.46)
    static let amber = Color(red: 0.86, green: 0.55, blue: 0.14)

    /// The tint for icons, chips, and selected states. It is the same jade as
    /// `action`, named separately so call sites read as intent rather than as
    /// a reference to the primary button color.
    static let accent = action

    /// The only label color placed on top of a filled `action` or `accent`
    /// surface. Both jade values are dark enough for white to clear AA.
    static let onAccent = Color.white
}

struct RankFolderBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    RankFolderPalette.action.opacity(0.095),
                    Color.clear,
                    RankFolderPalette.coral.opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [RankFolderPalette.action.opacity(0.08), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                colors: [RankFolderPalette.plum.opacity(0.055), Color.clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

struct SurfaceCard<Content: View>: View {
    @Environment(\.rankFolderPanelSpacing) private var panelSpacing
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20 * panelSpacing)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        RankFolderPalette.action.opacity(0.045),
                                        Color.clear,
                                        RankFolderPalette.coral.opacity(0.025)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: RankFolderPalette.action.opacity(0.035), radius: 14, y: 5)
            .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
    }
}

/// A stable-width primary action whose visible bounds match its hit region.
struct RankFolderPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rankFolderFont(.body, weight: .semibold)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .frame(minWidth: 168, minHeight: 36)
            .background(
                configuration.isPressed
                    ? RankFolderPalette.actionPressed
                    : RankFolderPalette.action,
                in: Capsule()
            )
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.48)
    }
}

struct RankFolderModelActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rankFolderFont(.body, weight: .semibold)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(
                    colors: [RankFolderPalette.coral, RankFolderPalette.plum],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(
                color: RankFolderPalette.plum.opacity(configuration.isPressed ? 0.08 : 0.24),
                radius: configuration.isPressed ? 4 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.46)
    }
}

struct RankFolderSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rankFolderFont(.body, weight: .semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(minWidth: 88, minHeight: 36)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.13 : 0.075),
                in: Capsule()
            )
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.42)
    }
}

struct SetupChecklist: View {
    @ObservedObject var automation: AutomationCoordinator
    let showFolderStep: Bool
    @State private var showingSecurityDetails = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(showFolderStep ? "Get started" : "Optional: automate Finder")
                        .rankFolderFont(.title2, weight: .semibold)
                    Text("Rank & Folder works without this. Turn it on only if you want saved layouts restored automatically inside Finder.")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)

                if showFolderStep {
                    SetupRow(
                        number: 1,
                        title: "Choose a folder",
                        detail: "Choose its sections and item order.",
                        isComplete: false,
                        buttonTitle: nil,
                        action: nil
                    )
                    Divider().padding(.leading, 44)
                }

                SetupRow(
                    number: showFolderStep ? 2 : 1,
                    title: "Turn on Finder automation",
                    detail: "Optional. Accessibility lets Rank & Folder notice the active folder and choose Finder’s existing view menus.",
                    isComplete: automation.accessibilityGranted,
                    isOptional: true,
                    buttonTitle: automation.accessibilityGranted
                        ? nil
                        : !automation.isRunningFromApplications
                            ? "Show app"
                            : automation.hasRequestedAccessibility ? "Check again" : "Allow…",
                    action: {
                        if !automation.isRunningFromApplications {
                            automation.revealRunningCopy()
                        } else if automation.hasRequestedAccessibility {
                            automation.checkAccessibilityPermission()
                        } else {
                            automation.requestAccessibilityPermission()
                        }
                    }
                )

                if !automation.accessibilityGranted
                    && (!automation.isRunningFromApplications || automation.hasRequestedAccessibility) {
                    Divider().padding(.leading, 44)
                    AccessibilityRecoveryView(automation: automation)
                }

                Divider().padding(.leading, 44)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingSecurityDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Label("What Accessibility allows", systemImage: "lock.shield")
                            .rankFolderFont(.callout, weight: .medium)
                        Spacer()
                        Image(systemName: showingSecurityDetails ? "chevron.down" : "chevron.right")
                            .rankFolderFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .accessibilityValue(showingSecurityDetails ? "Expanded" : "Collapsed")
                .accessibilityHint(showingSecurityDetails ? "Hide details" : "Show details")

                if showingSecurityDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("macOS grants broad Accessibility control. Rank & Folder’s implementation uses it only to read the focused Finder folder URL and choose Finder’s existing section and order controls.")
                        Label("No keystroke collection or global keyboard monitoring", systemImage: "keyboard.badge.ellipsis")
                        Label("No file-content reading or modification", systemImage: "doc.badge.ellipsis")
                        Label("No screenshots or telemetry; optional model connections are separately disclosed", systemImage: "network.slash")
                    }
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(showFolderStep ? "Getting started checklist" : "Optional Finder automation")
    }
}

private struct AccessibilityRecoveryView: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    @ObservedObject var automation: AutomationCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(automation.isRunningFromApplications
                    ? "This copy is not approved yet"
                    : "Move this copy before approving it")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(colorVisionMode.color(for: .warning))
            }

            Text(recoveryInstructions)
                .rankFolderFont(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(automation.runningAppURL.path(percentEncoded: false), systemImage: "app.dashed")
                .rankFolderFont(.caption, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if automation.isRunningFromApplications {
                    Button("Ask macOS again") {
                        automation.requestAccessibilityPermission()
                    }
                }
                Button("Show this copy in Finder") {
                    automation.revealRunningCopy()
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accessibility permission recovery")
    }

    private var recoveryInstructions: String {
        if automation.isRunningFromApplications {
            return "If Accessibility already shows Rank & Folder as On, macOS approved another copy or an earlier build. Remove that RankFolder row, click +, choose the copy below, and turn it on. This screen will recognize it automatically."
        }
        return "Accessibility approval follows a specific app copy. Move Rank & Folder to Applications, quit this copy, reopen the one in Applications, and approve it there."
    }
}

private struct SetupRow: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    let number: Int
    let title: String
    let detail: String
    let isComplete: Bool
    var isOptional = false
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete
                        ? colorVisionMode.color(for: .success).opacity(0.15)
                        : Color.secondary.opacity(0.10))
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colorVisionMode.color(for: .success))
                } else {
                    Text("\(number)")
                        .rankFolderFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if isComplete {
                Label("On", systemImage: "checkmark.circle.fill")
                    .rankFolderFont(.callout, weight: .medium)
                    .foregroundStyle(colorVisionMode.color(for: .success))
            } else if let buttonTitle, let action {
                Button(buttonTitle, action: action)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isComplete ? "On" : isOptional ? "Optional, off" : "Not complete")
    }
}

struct AutomationStatusBanner: View {
    @Environment(\.rankFolderColorVisionMode) private var colorVisionMode
    let status: AutomationStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if case .applying = status {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            } else {
                Image(systemName: status.systemImage)
                    .rankFolderFont(.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .fontWeight(.semibold)
                Text(status.message)
                    .rankFolderFont(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch status {
        case .ready, .applying: colorVisionMode.color(for: .information)
        case .applied: colorVisionMode.color(for: .success)
        case .needsSetup: colorVisionMode.color(for: .warning)
        case .failed: colorVisionMode.color(for: .danger)
        }
    }
}
