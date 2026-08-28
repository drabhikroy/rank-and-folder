import CoreFoundation
import Foundation

/// A one-bit cross-process signal. Darwin notifications carry no payload and
/// no sender identity, so they are used only to tell the other process that
/// shared storage changed. Everything that matters is then read from that
/// storage and verified there.
public enum DarwinNotification {
    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Listens for a system wide notification. The app and its Finder extension are
/// separate processes, so this is how one tells the other that something changed.
public final class DarwinNotificationObserver {
    private let name: String
    private let handler: () -> Void

    public init(name: String, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            rankFolderDarwinNotificationCallback,
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
    }

    fileprivate func receive() {
        handler()
    }
}

private func rankFolderDarwinNotificationCallback(
    _: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
) {
    guard let observer else { return }
    Unmanaged<DarwinNotificationObserver>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .receive()
}
