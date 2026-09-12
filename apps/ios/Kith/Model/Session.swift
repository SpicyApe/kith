// Session.swift — the only place supabase-swift is touched.
//
// The type is called `AuthSession` rather than `Session` because `Supabase` already
// exports a `Session` struct (the auth session) and shadowing it in this module makes
// every `client.auth.session` reference ambiguous to read.

import Foundation
import KithCore
import Supabase

/// Phone OTP sign-in plus a bearer token for `KithAPI`.
///
/// `SupabaseClient` is thread-safe (it serialises its own state internally) and the
/// only stored property here is an immutable `let`, so the wrapper is `@unchecked Sendable`.
final class AuthSession: AuthProviding, @unchecked Sendable {
    let client: SupabaseClient
    /// The session handed back by `verifyOTP`, kept as a fallback for `accessToken()`:
    /// the SDK's default storage is the Keychain, which an unsigned simulator build
    /// (CI, or a sideload without entitlements) can fail to write, leaving
    /// `client.auth.session` empty right after a successful sign-in.
    private let lock = NSLock()
    private var memorySession: Session?

    init(url: URL, anonKey: String) {
        #if DEBUG && targetEnvironment(simulator)
        // Simulator debug builds: persist the session in UserDefaults instead of the
        // Keychain, which needs entitlements an unsigned build does not have.
        let options = SupabaseClientOptions(auth: .init(storage: UserDefaultsAuthStorage()))
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey, options: options)
        #else
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        #endif
    }

    // MARK: AuthTokenProvider

    /// Current access token, refreshed by the SDK when it is close to expiry.
    /// Falls back to the in-memory session from the last verification, and returns nil
    /// (rather than throwing) when there is no session at all.
    func accessToken() async throws -> String? {
        do {
            return try await client.auth.session.accessToken
        } catch {
            let fallback = lock.withLock { memorySession }
            if let fallback, fallback.expiresAt > Date().timeIntervalSince1970 {
                return fallback.accessToken
            }
            return nil
        }
    }

    // MARK: Sign in

    func sendCode(phone: String) async throws {
        try await client.auth.signInWithOTP(phone: phone)
    }

    @discardableResult
    func verify(phone: String, code: String) async throws -> String? {
        let response = try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
        lock.withLock { memorySession = response.session }
        return response.user.id.uuidString.lowercased()
    }

    func signOut() async {
        lock.withLock { memorySession = nil }
        try? await client.auth.signOut()
    }

    /// The signed-in user's id, or nil when signed out.
    func currentUserId() async -> String? {
        if let session = try? await client.auth.session {
            return session.user.id.uuidString.lowercased()
        }
        return lock.withLock { memorySession }?.user.id.uuidString.lowercased()
    }

    var hasStoredSession: Bool {
        get async {
            (try? await client.auth.session) != nil
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// `AuthLocalStorage` backed by UserDefaults for simulator debug builds only, where the
/// Keychain is unreliable without code-signing entitlements. Never used in Release.
struct UserDefaultsAuthStorage: AuthLocalStorage {
    private let prefix = "kith.auth."

    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }

    func retrieve(key: String) throws -> Data? {
        UserDefaults.standard.data(forKey: prefix + key)
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}
#endif
