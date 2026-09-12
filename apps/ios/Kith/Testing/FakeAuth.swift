// FakeAuth.swift — the sign-in half of the test seam (apps/ios/TESTING.md §2).
// Debug-only, like `FakeKithAPI`, and locked the same way.

#if DEBUG

import Foundation
import KithCore

final class FakeAuth: AuthProviding, @unchecked Sendable {
    static let userId = "u-me"
    /// The only code `verify` accepts.
    static let validCode = "123456"

    /// An unsigned JWT (`alg: none`) whose `sub` claim is `u-me`, so anything that reads
    /// the claim — `SupabaseKithAPI.userId(fromJWT:)` — gets the right answer. Nothing
    /// verifies the signature client-side.
    static let token: String = {
        let header = base64URL("{\"alg\":\"none\",\"typ\":\"JWT\"}")
        let payload = base64URL("{\"sub\":\"u-me\",\"role\":\"authenticated\"}")
        return "\(header).\(payload)."
    }()

    private let lock = NSLock()
    private var signedIn: Bool
    private var recordedCalls: [String] = []

    init(signedIn: Bool = false) {
        self.signedIn = signedIn
    }

    /// Every call made, in order. Same shape as `FakeKithAPI.calls`.
    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    // MARK: AuthTokenProvider

    func accessToken() async throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return signedIn ? Self.token : nil
    }

    // MARK: AuthProviding

    func sendCode(phone: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("sendCode(\(phone))")
    }

    @discardableResult
    func verify(phone: String, code: String) async throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("verify(\(code))")
        guard code == Self.validCode else {
            throw KithError.api(status: 400, code: "invalid_code", message: "That code didn't work.")
        }
        signedIn = true
        return Self.userId
    }

    func signOut() async {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("signOut")
        signedIn = false
    }

    func currentUserId() async -> String? {
        lock.lock()
        defer { lock.unlock() }
        return signedIn ? Self.userId : nil
    }

    // MARK: Helpers

    private static func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#endif
