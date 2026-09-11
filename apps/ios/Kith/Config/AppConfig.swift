// AppConfig.swift — build-time configuration read from `Config.plist`.
//
// `Config.plist` is gitignored. Copy `Config.example.plist` next to it and fill in
// the three values before running the app. XcodeGen bundles everything under
// `Kith/`, so the plist lands in the app bundle's resources.

import Foundation

enum AppConfig {
    static let supabaseURLKey = "SUPABASE_URL"
    static let supabaseAnonKeyKey = "SUPABASE_ANON_KEY"
    static let webBaseKey = "WEB_BASE"

    /// Every string entry of `Config.plist`, or an empty dictionary when the file is absent.
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in dictionary {
            if let string = value as? String, !string.isEmpty {
                result[key] = string
            }
        }
        return result
    }()

    private static func require(_ key: String, fallback: String) -> String {
        if let value = values[key] {
            return value
        }
        // Deliberately not `assertionFailure`: a missing Config.plist is a setup
        // mistake, not a programmer error, and trapping on launch hides the message
        // behind a crash. `RootView` shows a banner instead (see `isConfigured`).
        print("""
        Kith: missing "\(key)" in Config.plist.
        Copy apps/ios/Kith/Config/Config.example.plist to apps/ios/Kith/Config/Config.plist \
        and fill in SUPABASE_URL, SUPABASE_ANON_KEY and WEB_BASE.
        """)
        return fallback
    }

    /// False when any of the three required keys is missing, i.e. the app is running on
    /// its placeholder fallbacks and every network call will fail.
    static let isConfigured: Bool =
        values[supabaseURLKey] != nil && values[supabaseAnonKeyKey] != nil && values[webBaseKey] != nil

    static let supabaseURL: URL = {
        let raw = require(supabaseURLKey, fallback: "https://unconfigured.supabase.co")
        return URL(string: raw) ?? URL(string: "https://unconfigured.supabase.co")!
    }()

    static let supabaseAnonKey: String = require(supabaseAnonKeyKey, fallback: "unconfigured")

    static let webBase: URL = {
        let raw = require(webBaseKey, fallback: "https://kith.app")
        return URL(string: raw) ?? URL(string: "https://kith.app")!
    }()

    /// Host of `webBase`, used to recognise universal links ("kith.app").
    static var webHost: String { webBase.host ?? "kith.app" }

    /// APNs environment string sent to `register-device`.
    static var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
