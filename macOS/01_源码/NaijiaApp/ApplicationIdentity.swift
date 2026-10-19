import Foundation

enum ApplicationIdentity {
    static var displayName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { return name }
        #if DEBUG
        return "奶家族测试版"
        #else
        return "奶家族"
        #endif
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }

    // Preserve existing progress in the renamed test app; user builds never read that directory.
    static var dataDirectory: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "NaijiaDataDirectory") as? String,
           !configured.isEmpty, !configured.contains("/") { return configured }
        #if DEBUG
        return "奶家"
        #else
        return "奶家族"
        #endif
    }
}
