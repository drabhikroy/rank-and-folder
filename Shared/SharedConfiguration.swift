import Foundation

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

public extension UserDefaults {
    static var rankFolderShared: UserDefaults {
        UserDefaults(suiteName: SharedConfiguration.appGroupIdentifier) ?? .standard
    }
}
