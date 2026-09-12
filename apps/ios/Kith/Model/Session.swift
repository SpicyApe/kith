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

    init(url: URL, anonKey: String) {
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    // MARK: AuthTokenProvider

    /// Current access token, refreshed by the SDK when it is close to expiry.
    /// Returns nil (rather than throwing) when there is no stored session at all.
    func accessToken() async throws -> String? {
        do {
            return try await client.auth.session.accessToken
        } catch {
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
        return response.user.id.uuidString.lowercased()
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    /// The signed-in user's id, or nil when signed out.
    func currentUserId() async -> String? {
        guard let session = try? await client.auth.session else { return nil }
        return session.user.id.uuidString.lowercased()
    }

    var hasStoredSession: Bool {
        get async {
            (try? await client.auth.session) != nil
        }
    }
}
