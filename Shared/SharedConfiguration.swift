import Foundation

/// The identifiers and notification names the app and its Finder extension both
/// need, kept in one place so the two processes cannot disagree.
public enum SharedConfiguration {
    public static var includesFinderExtension: Bool {
        Bundle.main.object(forInfoDictionaryKey: "RankFolderIncludesFinderExtension") as? Bool
            ?? false
    }

    public static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "RankFolderAppGroupIdentifier") as? String
            ?? "group.dev.rankandfolder.RankAndFolder"
    }

    public static var applyRequestNotification: String {
        "\(appGroupIdentifier).apply-requested"
    }

    public static var profilesChangedNotification: String {
        "\(appGroupIdentifier).profiles-changed"
    }
}

/// The shared preference suite, which is what lets the app and the extension see
/// the same saved layouts.
public extension UserDefaults {
    static var rankFolderShared: UserDefaults {
        UserDefaults(suiteName: SharedConfiguration.appGroupIdentifier) ?? .standard
    }
}
