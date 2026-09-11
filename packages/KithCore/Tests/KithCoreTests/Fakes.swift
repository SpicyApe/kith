// Fakes.swift — shared test doubles for KithCoreTests. Not a test case itself.

import Foundation
@testable import KithCore

/// Records every request it receives, in order, and returns queued responses
/// (or throws queued errors) in FIFO order. Used to assert `SupabaseKithAPI`'s
/// request shape without touching the network.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    private var results: [Result<HTTPResponse, Error>] = []

    func queue(_ response: HTTPResponse) {
        results.append(.success(response))
    }

    func queue(status: Int, body: Data = Data()) {
        results.append(.success(HTTPResponse(status: status, body: body)))
    }

    func queue(throwing error: Error) {
        results.append(.failure(error))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !results.isEmpty else {
            fatalError("FakeHTTPClient: no response queued for \(request.method.rawValue) \(request.url)")
        }
        switch results.removeFirst() {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

/// Returns a fixed token (or nil, simulating signed-out) without touching any real
/// auth SDK.
final class FakeAuth: AuthTokenProvider, @unchecked Sendable {
    var token: String?
    init(token: String? = nil) { self.token = token }
    func accessToken() async throws -> String? { token }
}

/// A generic transport failure, distinct from any KithCore error type, for
/// asserting that transport-layer throws map to `KithError.network`.
struct DummyTransportError: Error, Equatable {}

/// Builds a syntactically valid, unsigned JWT ("header.payload.signature", each part
/// base64url) whose payload carries only `{"sub": sub}` — enough for
/// `SupabaseKithAPI.userId(fromJWT:)` and for code that reads the `sub` claim (e.g.
/// `createCircle`'s `owner_id`). The signature segment is the literal string "sig";
/// nothing checks it.
func makeJWT(sub: String) -> String {
    let header = base64URLEncode(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
    let payload = base64URLEncode(Data(#"{"sub":"\#(sub)"}"#.utf8))
    return "\(header).\(payload).sig"
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
