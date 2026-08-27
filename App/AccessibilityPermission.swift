import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func request() -> Bool {
        // Use the documented key's stable string value directly. The SDK
        // imports kAXTrustedCheckOptionPrompt as mutable global state, which
        // produces a false-positive data-race warning under Swift 6 checking.
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
