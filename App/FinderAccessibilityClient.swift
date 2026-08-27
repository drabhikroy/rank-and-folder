import AppKit
import ApplicationServices
import Foundation

enum FinderAccessibilityError: LocalizedError {
    case permissionRequired
    case finderNotRunning
    case finderNotActive
    case noFinderWindow
    case cannotReadFinderLocation(String)
    case unexpectedFolder(expected: String, actual: String)
    case menuItemNotFound(String)
    case groupControlNotFound(Int)
    case sortControlNotFound(Int)
    case accessibilityActionFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Accessibility permission is required."
        case .finderNotRunning:
            "Finder is not running."
        case .finderNotActive:
            "Finder is not the active app, so no view was changed."
        case .noFinderWindow:
            "Finder does not have a focused folder window."
        case .cannotReadFinderLocation(let diagnostic):
            "Rank & Folder could not verify the focused Finder folder. \(diagnostic)"
        case .unexpectedFolder(let expected, let actual):
            "Finder is showing \(actual), not \(expected), so no view was changed."
        case .menuItemNotFound(let title):
            "Finder menu item “\(title)” was not found. This build expects Finder’s English control titles."
        case .groupControlNotFound(let controlCount):
            "Finder’s toolbar did not expose a labeled Group control (\(controlCount) toolbar controls found)."
        case .sortControlNotFound(let popupCount):
            "Finder’s View Options did not expose a labeled Sort By control (\(popupCount) pop-up controls found)."
        case .accessibilityActionFailed(let title, let error):
            "Finder rejected the “\(title)” menu action (AX error \(error.rawValue))."
        }
    }

    var canRetryAfterFinderNavigation: Bool {
        switch self {
        case .finderNotActive, .noFinderWindow, .cannotReadFinderLocation, .unexpectedFolder:
            true
        case .permissionRequired, .finderNotRunning, .menuItemNotFound, .groupControlNotFound,
                .sortControlNotFound, .accessibilityActionFailed:
            false
        }
    }
}

enum FinderFolderVerification {
    case exactLocation
    case explicitOpen(expectedTitle: String, validUntil: Date)
}

enum FinderVerificationOutcome {
    case exactLocation
    case explicitOpenTitle
}

/// Validates the focused Finder URL against identity captured by the caller.
/// Returning false fails closed and prevents the next Finder action.
typealias FinderFocusedURLValidator = (URL) -> Bool

/// The single adapter that knows about Finder's current UI. Keeping this layer
/// isolated lets a future implementation replace menu automation without
/// changing profile storage, inheritance, or the Finder Sync extension.
/// The only component that knows what Finder's interface looks like.
///
/// Finder exposes no public API for grouping and sorting, so this reads the
/// same Accessibility tree a screen reader would and presses the same controls
/// a person would. That makes it dependent on Finder's English control titles
/// and on its current layout, which differ across macOS versions. Every path
/// therefore verifies the focused folder before each of the two changes and
/// throws rather than acting on a folder it cannot confirm.
///
/// Keeping this knowledge in one file means a future macOS release can be
/// handled here without touching storage, inheritance, or the extension.
final class FinderAccessibilityClient {
    private let menuPause: TimeInterval = 0.04

    func focusedFolderURL() throws -> URL {
        let application = try activeFinderApplication()
        return try focusedFolderURL(in: application)
    }

    @discardableResult
    func apply(
        targetFolderURL: URL,
        recipe: FinderRecipeRepresentation,
        verification: FinderFolderVerification = .exactLocation,
        focusedURLValidator: FinderFocusedURLValidator? = nil
    ) throws -> FinderVerificationOutcome {
        let application = try activeFinderApplication()
        let initialOutcome = try verifyFocusedFolder(
            application,
            expected: targetFolderURL,
            verification: verification,
            focusedURLValidator: focusedURLValidator
        )

        try chooseGroupCriterion(recipe.groupBy, application: application)

        // Grouping can take long enough for the user to navigate or for a path
        // to be replaced. Reacquire the active Finder instance and revalidate
        // the focused target immediately before making the second change.
        // Reacquire Finder rather than reusing the earlier reference. The
        // application element is cheap to recreate and the process may have
        // been replaced while the grouping change was in progress.
        let preSortApplication = try activeFinderApplication()
        let preSortOutcome = try verifyFocusedFolder(
            preSortApplication,
            expected: targetFolderURL,
            verification: verification,
            focusedURLValidator: focusedURLValidator
        )
        try chooseSortCriterion(recipe.sortBy, application: preSortApplication)

        if case .explicitOpenTitle = initialOutcome {
            return .explicitOpenTitle
        }
        return preSortOutcome
    }

    private func activeFinderApplication() throws -> AXUIElement {
        guard AccessibilityPermission.isGranted else {
            throw FinderAccessibilityError.permissionRequired
        }

        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder")
            .first else {
            throw FinderAccessibilityError.finderNotRunning
        }

        guard finder.isActive else {
            throw FinderAccessibilityError.finderNotActive
        }

        return AXUIElementCreateApplication(finder.processIdentifier)
    }

    private func verifyFocusedFolder(
        _ application: AXUIElement,
        expected: URL,
        verification: FinderFolderVerification,
        focusedURLValidator: FinderFocusedURLValidator?
    ) throws -> FinderVerificationOutcome {
        do {
            let actualURL = try focusedFolderURL(in: application)
            let matchesExpectedTarget = focusedURLValidator?(actualURL)
                ?? RankFolderProfile.urlsReferToSameItem(expected, actualURL)
            guard matchesExpectedTarget else {
                throw FinderAccessibilityError.unexpectedFolder(
                    expected: expected.lastPathComponent,
                    actual: actualURL.lastPathComponent
                )
            }
            return .exactLocation
        } catch let error as FinderAccessibilityError {
            guard case .cannotReadFinderLocation = error,
                  case .explicitOpen(let expectedTitle, let validUntil) = verification,
                  Date() <= validUntil else {
                throw error
            }

            let actualTitle = try focusedFolderTitle(in: application)
            guard titlesMatch(expectedTitle, actualTitle) else {
                throw FinderAccessibilityError.unexpectedFolder(
                    expected: expectedTitle,
                    actual: actualTitle
                )
            }
            return .explicitOpenTitle
        }
    }

    private func focusedFolderTitle(in application: AXUIElement) throws -> String {
        let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, of: application)
        let mainWindow = elementAttribute(kAXMainWindowAttribute, of: application)
        if let focusedWindow,
           let title = stringAttribute(kAXTitleAttribute, of: focusedWindow),
           !title.isEmpty {
            return title
        }
        if let mainWindow,
           let title = stringAttribute(kAXTitleAttribute, of: mainWindow),
           !title.isEmpty {
            return title
        }
        throw FinderAccessibilityError.cannotReadFinderLocation(
            "Finder also omitted the focused window title."
        )
    }

    private func titlesMatch(_ expected: String, _ actual: String) -> Bool {
        let normalizedExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedActual = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedExpected.compare(
            normalizedActual,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: .current
        ) == .orderedSame
    }

    private func focusedFolderURL(in application: AXUIElement) throws -> URL {
        let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, of: application)
        let mainWindow = elementAttribute(kAXMainWindowAttribute, of: application)
        guard focusedWindow != nil || mainWindow != nil else {
            throw FinderAccessibilityError.noFinderWindow
        }

        var diagnostics: [String] = []
        if let focusedWindow {
            let result = folderURL(from: focusedWindow, label: "Focused window")
            if let url = result.url { return url }
            diagnostics.append(contentsOf: result.diagnostics)
        }

        if let mainWindow,
           focusedWindow.map({ !CFEqual($0, mainWindow) }) ?? true {
            let result = folderURL(from: mainWindow, label: "Main window")
            if let url = result.url { return url }
            diagnostics.append(contentsOf: result.diagnostics)
        }

        throw FinderAccessibilityError.cannotReadFinderLocation(
            "Diagnostic: \(diagnostics.joined(separator: "; "))."
        )
    }

    private func folderURL(
        from window: AXUIElement,
        label: String
    ) -> (url: URL?, diagnostics: [String]) {
        var diagnostics: [String] = []

        if let document = stringAttribute(kAXDocumentAttribute, of: window),
           let documentURL = finderDocumentURL(from: document) {
            return (documentURL, diagnostics)
        }
        diagnostics.append("\(label) AXDocument unavailable")

        // Finder and File Provider locations can expose AXURL as a CFURL when
        // AXDocument is unavailable.
        if let locationURL = urlAttribute(kAXURLAttribute, of: window) {
            if locationURL.isFileURL { return (locationURL, diagnostics) }
            diagnostics.append("\(label) AXURL was not a file URL")
        } else {
            diagnostics.append("\(label) AXURL unavailable")
        }

        // Finder windows commonly expose their current folder through the
        // standard document-proxy element in the title bar. The proxy's AXURL
        // still identifies the window itself, not a selected file or sidebar
        // item, so it preserves the strict focused-folder safety check.
        guard let proxy = elementAttribute(kAXProxyAttribute, of: window) else {
            diagnostics.append("\(label) AXProxy unavailable")
            return (nil, diagnostics)
        }

        if let proxyURL = urlAttribute(kAXURLAttribute, of: proxy) {
            if proxyURL.isFileURL { return (proxyURL, diagnostics) }
            diagnostics.append("\(label) proxy AXURL was not a file URL")
        } else {
            diagnostics.append("\(label) proxy AXURL unavailable")
        }

        if let proxyDocument = stringAttribute(kAXDocumentAttribute, of: proxy),
           let proxyDocumentURL = finderDocumentURL(from: proxyDocument) {
            return (proxyDocumentURL, diagnostics)
        }
        diagnostics.append("\(label) proxy AXDocument unavailable")
        return (nil, diagnostics)
    }

    private func finderDocumentURL(from value: String) -> URL? {
        if let url = URL(string: value), url.isFileURL {
            return url
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return nil
    }

    private func chooseGroupCriterion(
        _ criterion: GroupCriterion,
        application: AXUIElement
    ) throws {
        // Tahoe documents grouping through Finder's toolbar Group control.
        // This works whether the folder is already grouped or not.
        if #available(macOS 26.0, *) {
            do {
                if try chooseToolbarGroupCriterion(
                    criterion.finderMenuTitle,
                    application: application
                ) {
                    return
                }
            } catch let error as FinderAccessibilityError {
                guard case .menuItemNotFound = error else { throw error }
                // A customized or overflowed toolbar can make the button's
                // menu transiently unavailable. Continue with Finder's menu
                // compatibility path after the button has been dismissed.
            }
        }

        // Finder's View menu is the fallback when the toolbar control is not available.
        // Some layouts hide Group By until Use Groups has been enabled.
        do {
            try chooseMenuItem(
                application: application,
                menuName: "View",
                submenuName: "Group By",
                itemName: criterion.finderMenuTitle
            )
        } catch let error as FinderAccessibilityError {
            guard case .menuItemNotFound(let missingItem) = error,
                  missingItem == "Group By" else {
                throw error
            }

            if criterion == .none { return }
            try pressMenuCommand(
                application: application,
                menuName: "View",
                commandNames: ["Use Groups"]
            )
            try chooseMenuItem(
                application: application,
                menuName: "View",
                submenuName: "Group By",
                itemName: criterion.finderMenuTitle
            )
        }
    }

    private func chooseToolbarGroupCriterion(
        _ itemName: String,
        application: AXUIElement
    ) throws -> Bool {
        guard let window = folderWindow(in: application),
              let toolbar = findDescendant(
                role: kAXToolbarRole as String,
                in: window,
                limit: 240
              ) else {
            return false
        }

        let acceptedRoles = Set([
            kAXButtonRole as String,
            kAXMenuButtonRole as String,
            kAXPopUpButtonRole as String
        ])
        let controls = descendantElements(in: toolbar, limit: 240).filter {
            guard let role = stringAttribute(kAXRoleAttribute, of: $0) else { return false }
            return acceptedRoles.contains(role)
        }

        guard let groupControl = controls.first(where: {
            control($0, hasLabelContaining: "group")
        }) else {
            return false
        }

        try perform(kAXPressAction, on: groupControl, named: "Group")
        guard let criterionItem = waitForOpenedMenuItem(
            titled: itemName,
            from: groupControl,
            attempts: 6
        ) else {
            try? perform(kAXPressAction, on: groupControl, named: "Group")
            throw FinderAccessibilityError.menuItemNotFound(itemName)
        }

        try perform(kAXPressAction, on: criterionItem, named: itemName)
        pause(0.08)
        return true
    }

    private func chooseMenuItem(
        application: AXUIElement,
        menuName: String,
        submenuName: String,
        itemName: String
    ) throws {
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, of: application),
              let menuBarItem = findDescendant(
                titled: menuName,
                role: kAXMenuBarItemRole as String,
                in: menuBar
              ) else {
            throw FinderAccessibilityError.menuItemNotFound(menuName)
        }

        try perform(kAXPressAction, on: menuBarItem, named: menuName)
        guard let submenuItem = waitForDescendant(
            titled: submenuName,
            role: kAXMenuItemRole as String,
            in: menuBarItem,
            attempts: 4
        ) else {
            try? perform(kAXPressAction, on: menuBarItem, named: menuName)
            throw FinderAccessibilityError.menuItemNotFound(submenuName)
        }

        try perform(kAXPressAction, on: submenuItem, named: submenuName)
        guard let criterionItem = waitForDescendant(
            titled: itemName,
            role: kAXMenuItemRole as String,
            in: submenuItem,
            attempts: 4
        ) else {
            try? perform(kAXPressAction, on: menuBarItem, named: menuName)
            throw FinderAccessibilityError.menuItemNotFound(itemName)
        }

        try perform(kAXPressAction, on: criterionItem, named: itemName)
        pause(0.08)
    }

    private func chooseSortCriterion(
        _ criterion: SortCriterion,
        application: AXUIElement
    ) throws {
        if #available(macOS 26.0, *) {
            try chooseSortCriterionInViewOptions(
                criterion.finderMenuTitle,
                application: application
            )
            return
        }

        do {
            try chooseMenuItem(
                application: application,
                menuName: "View",
                submenuName: "Sort By",
                itemName: criterion.finderMenuTitle
            )
        } catch let error as FinderAccessibilityError {
            guard case .menuItemNotFound(let missingItem) = error,
                  missingItem == "Sort By" else {
                throw error
            }
            try chooseSortCriterionInViewOptions(
                criterion.finderMenuTitle,
                application: application
            )
        }
    }

    private func chooseSortCriterionInViewOptions(
        _ itemName: String,
        application: AXUIElement
    ) throws {
        let openedViewOptions = try revealViewOptions(in: application)
        guard let sortPopup = waitForLabeledPopup(
            "sortby",
            application: application,
            attempts: 8
        ) else {
            let popupCount = viewOptionRoots(in: application).reduce(0) {
                $0 + descendants(
                    role: kAXPopUpButtonRole as String,
                    in: $1,
                    limit: 600
                ).count
            }
            throw FinderAccessibilityError.sortControlNotFound(popupCount)
        }

        try perform(kAXPressAction, on: sortPopup, named: "Sort By")
        guard let criterionItem = waitForOpenedMenuItem(
            titled: itemName,
            from: sortPopup,
            attempts: 6
        ) else {
            throw FinderAccessibilityError.menuItemNotFound(itemName)
        }
        try perform(kAXPressAction, on: criterionItem, named: itemName)
        pause(0.08)

        if openedViewOptions {
            try? pressMenuCommand(
                application: application,
                menuName: "View",
                commandNames: ["Hide View Options"]
            )
        }
    }

    private func revealViewOptions(in application: AXUIElement) throws -> Bool {
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, of: application),
              let viewMenu = findDescendant(
                titled: "View",
                role: kAXMenuBarItemRole as String,
                in: menuBar
              ) else {
            throw FinderAccessibilityError.menuItemNotFound("View")
        }

        try perform(kAXPressAction, on: viewMenu, named: "View")
        for _ in 0..<5 {
            if let show = findDescendant(
                titled: "Show View Options",
                role: kAXMenuItemRole as String,
                in: viewMenu
            ) {
                try perform(kAXPressAction, on: show, named: "Show View Options")
                pause(0.06)
                return true
            }
            if findDescendant(
                titled: "Hide View Options",
                role: kAXMenuItemRole as String,
                in: viewMenu
            ) != nil {
                try? perform(kAXPressAction, on: viewMenu, named: "View")
                return false
            }
            pause()
        }

        try? perform(kAXPressAction, on: viewMenu, named: "View")
        throw FinderAccessibilityError.menuItemNotFound("Show View Options")
    }

    private func pressMenuCommand(
        application: AXUIElement,
        menuName: String,
        commandNames: [String]
    ) throws {
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, of: application),
              let menuBarItem = findDescendant(
                titled: menuName,
                role: kAXMenuBarItemRole as String,
                in: menuBar
              ) else {
            throw FinderAccessibilityError.menuItemNotFound(menuName)
        }

        try perform(kAXPressAction, on: menuBarItem, named: menuName)
        for _ in 0..<5 {
            for commandName in commandNames {
                if let command = findDescendant(
                    titled: commandName,
                    role: kAXMenuItemRole as String,
                    in: menuBarItem
                ) {
                    try perform(kAXPressAction, on: command, named: commandName)
                    pause(0.06)
                    return
                }
            }
            pause()
        }

        try? perform(kAXPressAction, on: menuBarItem, named: menuName)
        throw FinderAccessibilityError.menuItemNotFound(commandNames.joined(separator: " / "))
    }

    private func waitForLabeledPopup(
        _ label: String,
        application: AXUIElement,
        attempts: Int
    ) -> AXUIElement? {
        for _ in 0..<attempts {
            for root in viewOptionRoots(in: application) {
                if let popup = findPopup(labeled: label, in: root) { return popup }
            }
            pause()
        }
        return nil
    }

    /// Finds the Sort By control in View Options. The control is matched by its
    /// own label first. When Finder gives the control no label of its own, the
    /// nearby static text is located instead and the search walks up a few
    /// levels, accepting a pop-up only when exactly one sits beside that label.
    /// Ambiguity returns nil, which fails the operation rather than pressing an
    /// unrelated control.
    private func findPopup(labeled label: String, in root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var cursor = 0
        var visited = 0
        var labelElements: [AXUIElement] = []

        while cursor < queue.count, visited < 600 {
            let element = queue[cursor]
            cursor += 1
            visited += 1
            let role = stringAttribute(kAXRoleAttribute, of: element)
            if role == kAXPopUpButtonRole as String,
               control(element, hasLabelContaining: label) {
                return element
            }
            if role == kAXStaticTextRole as String,
               elementLabels(element).contains(where: {
                   normalizedLabel($0).hasPrefix(label)
               }) {
                labelElements.append(element)
            }
            queue.append(contentsOf: children(of: element))
        }

        for labelElement in labelElements {
            var ancestor = elementAttribute(kAXParentAttribute, of: labelElement)
            for _ in 0..<3 {
                guard let current = ancestor else { break }
                let nearby = descendants(
                    role: kAXPopUpButtonRole as String,
                    in: current,
                    limit: 80
                )
                if nearby.count == 1 { return nearby[0] }
                ancestor = elementAttribute(kAXParentAttribute, of: current)
            }
        }
        return nil
    }

    private func waitForOpenedMenuItem(
        titled title: String,
        from control: AXUIElement,
        attempts: Int
    ) -> AXUIElement? {
        for _ in 0..<attempts {
            let roots = [
                elementAttribute(kAXShownMenuUIElementAttribute, of: control),
                focusedMenu(),
                control
            ].compactMap { $0 }
            for root in roots {
                if let item = findDescendant(
                    titled: title,
                    role: kAXMenuItemRole as String,
                    in: root,
                    limit: 160
                ) {
                    return item
                }
            }
            pause()
        }
        return nil
    }

    private func focusedMenu() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var current = elementAttribute(kAXFocusedUIElementAttribute, of: systemWide)
        for _ in 0..<8 {
            guard let element = current else { return nil }
            if stringAttribute(kAXRoleAttribute, of: element) == kAXMenuRole as String {
                return element
            }
            current = elementAttribute(kAXParentAttribute, of: element)
        }
        return nil
    }

    private func folderWindow(in application: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXMainWindowAttribute, of: application)
            ?? elementAttribute(kAXFocusedWindowAttribute, of: application)
    }

    private func viewOptionRoots(in application: AXUIElement) -> [AXUIElement] {
        let focused = elementAttribute(kAXFocusedWindowAttribute, of: application)
        let main = elementAttribute(kAXMainWindowAttribute, of: application)
        let windows = elementsAttribute(kAXWindowsAttribute, of: application)

        var roots: [AXUIElement] = []
        func appendUnique(_ element: AXUIElement?) {
            guard let element,
                  !roots.contains(where: { CFEqual($0, element) }) else { return }
            roots.append(element)
        }

        appendUnique(focused)
        for window in windows where main.map({ !CFEqual($0, window) }) ?? true {
            appendUnique(window)
        }
        appendUnique(main)
        return roots
    }

    private func control(_ element: AXUIElement, hasLabelContaining label: String) -> Bool {
        elementLabels(element).contains {
            normalizedLabel($0).contains(label)
        }
    }

    private func elementLabels(_ element: AXUIElement) -> [String] {
        var labels = [
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXValueAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
            stringAttribute(kAXHelpAttribute, of: element),
            stringAttribute(kAXIdentifierAttribute, of: element)
        ].compactMap { $0 }
        if let titleElement = elementAttribute(kAXTitleUIElementAttribute, of: element) {
            labels.append(stringAttribute(kAXTitleAttribute, of: titleElement) ?? "")
            labels.append(stringAttribute(kAXValueAttribute, of: titleElement) ?? "")
        }
        return labels
    }

    private func normalizedLabel(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
    }

    private func perform(_ action: String, on element: AXUIElement, named: String) throws {
        let error = AXUIElementPerformAction(element, action as CFString)
        guard error == .success else {
            throw FinderAccessibilityError.accessibilityActionFailed(named, error)
        }
    }

    private func findDescendant(
        titled title: String,
        role expectedRole: String,
        in root: AXUIElement,
        limit: Int = 600
    ) -> AXUIElement? {
        var queue = children(of: root)
        var cursor = 0
        var visited = 0

        while cursor < queue.count, visited < limit {
            let element = queue[cursor]
            cursor += 1
            visited += 1
            if stringAttribute(kAXTitleAttribute, of: element) == title,
               stringAttribute(kAXRoleAttribute, of: element) == expectedRole {
                return element
            }
            queue.append(contentsOf: children(of: element))
        }
        return nil
    }

    private func findDescendant(
        role expectedRole: String,
        in root: AXUIElement,
        limit: Int
    ) -> AXUIElement? {
        var queue = children(of: root)
        var cursor = 0
        var visited = 0
        while cursor < queue.count, visited < limit {
            let element = queue[cursor]
            cursor += 1
            visited += 1
            if stringAttribute(kAXRoleAttribute, of: element) == expectedRole {
                return element
            }
            queue.append(contentsOf: children(of: element))
        }
        return nil
    }

    private func waitForDescendant(
        titled title: String,
        role expectedRole: String,
        in root: AXUIElement,
        attempts: Int
    ) -> AXUIElement? {
        for _ in 0..<attempts {
            if let element = findDescendant(titled: title, role: expectedRole, in: root) {
                return element
            }
            pause(0.12)
        }
        return nil
    }

    private func descendants(
        role expectedRole: String,
        in root: AXUIElement,
        limit: Int
    ) -> [AXUIElement] {
        descendantElements(in: root, limit: limit).filter {
            stringAttribute(kAXRoleAttribute, of: $0) == expectedRole
        }
    }

    private func descendantElements(
        in root: AXUIElement,
        limit: Int,
        includeRoot: Bool = false
    ) -> [AXUIElement] {
        var queue = includeRoot ? [root] : children(of: root)
        var cursor = 0
        var result: [AXUIElement] = []
        while cursor < queue.count, result.count < limit {
            let element = queue[cursor]
            cursor += 1
            result.append(element)
            queue.append(contentsOf: children(of: element))
        }
        return result
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        // The type identifier was checked above. AXUIElement is a CoreFoundation
        // type that does not bridge through a conditional cast, so the reference
        // is reinterpreted directly rather than force cast.
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func elementsAttribute(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func urlAttribute(_ attribute: String, of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        if CFGetTypeID(value) == CFURLGetTypeID() {
            return value as? URL
        }
        if let string = value as? String {
            return finderDocumentURL(from: string)
        }
        return nil
    }

    private func pause(_ duration: TimeInterval? = nil) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: duration ?? menuPause))
    }
}
