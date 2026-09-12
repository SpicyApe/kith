// AuthProviding.swift — the auth seam (apps/ios/TESTING.md §1).
//
// `AppModel` talks to this protocol, never to `AuthSession` directly, so the unit
// tests and the `-uiTesting` launch can swap in `FakeAuth`. It refines
// `KithCore.AuthTokenProvider`, which is where `accessToken()` (and `Sendable`)
// come from, so a single existential covers both the sign-in flow and the bearer
// token `SupabaseKithAPI` needs.

import Foundation
import KithCore

protocol AuthProviding: AuthTokenProvider {
    /// Sends a one-time code by SMS. `phone` is E.164 ("+15551234567").
    func sendCode(phone: String) async throws

    /// Verifies the code and returns the signed-in user's id, or nil when the
    /// provider cannot supply one. Throws when the code is wrong.
    func verify(phone: String, code: String) async throws -> String?

    /// Drops the stored session. Never throws: signing out locally always "works".
    func signOut() async

    /// The signed-in user's id, or nil when signed out.
    func currentUserId() async -> String?
}
