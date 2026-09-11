// HTTP.swift — the seam between KithCore and the network / auth SDK.
//
// CONTRACT FILE. The app target implements `HTTPClient` with URLSession and
// `AuthTokenProvider` with supabase-swift; tests use fakes. KithCore never imports
// a Supabase SDK.

import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }
    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public protocol AuthTokenProvider: Sendable {
    /// A currently valid access token (JWT) for the signed-in user, refreshed if needed. Nil when signed out.
    func accessToken() async throws -> String?
}

/// Errors surfaced to the UI layer. `api` carries the server's stable `code`.
public enum KithError: Error, Equatable, Sendable {
    case notSignedIn
    case network(String)
    /// 4xx from an edge function or PostgREST, with the server's code (e.g. "already_played") and message.
    case api(status: Int, code: String, message: String)
    case decoding(String)
}
