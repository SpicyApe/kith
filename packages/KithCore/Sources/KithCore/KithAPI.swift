// KithAPI.swift — the client's view of the backend.
//
// CONTRACT FILE. `KithAPI` is what view models depend on. `SupabaseKithAPI` is the
// real implementation over HTTPClient + AuthTokenProvider, targeting PostgREST
// (`/rest/v1/...`) and edge functions (`/functions/v1/...`). Implementers fill the
// bodies of SupabaseKithAPI only; the protocol and doc comments are frozen.

import Foundation
import GridGames
import LineupEngine

public protocol KithAPI: Sendable {
    // Edge functions
    func register(displayName: String, tz: String) async throws -> RegisterResponse
    func submitResult(puzzleDate: String, tz: String, attempts: [Attempt]) async throws -> SubmitResponse
    func matchContacts(added: [String], removed: [String], full: Bool) async throws -> MatchResponse
    func deleteAccount() async throws

    // RPCs
    /// `start_puzzle(d)`; the jsonb it returns decodes directly into `LineupEngine.Puzzle`.
    func startPuzzle(date: String) async throws -> Puzzle
    /// `board(kind, scope_id, period, for_date, game_kind)`; `game` picks the column (Lineup by default).
    func board(kind: BoardKind, scopeId: String?, period: BoardPeriod, date: String, game: BoardGame) async throws -> [BoardRow]
    func joinCircle(code: String) async throws -> String

    // Games hub (docs/07)
    /// RPC `start_game(d, g)`.
    func startGame(date: String, game: GameKind) async throws -> StartedGame
    /// Edge function `submit-game`; `answer` is nil only when `gaveUp`.
    func submitGame(date: String, game: GameKind, tz: String, elapsedMs: Int, mistakes: Int,
                    gaveUp: Bool, answer: GameAnswer?) async throws -> SubmitGameResponse
    /// `game_results?select=date,game,elapsed_ms,mistakes,solved,gave_up,score&user_id=eq.<me>&date=gte.<since>&order=date.asc`.
    func myGameResults(sinceDate: String) async throws -> [GameResultSummary]
    /// `daily_games?select=date,game,number,difficulty&date=eq.<date>&order=game.asc` (RLS limits to the ±14 h window).
    func dailyGames(date: String) async throws -> [DailyGameRow]
    func myStreak() async throws -> Int
    func track(_ name: String, props: [String: String]) async throws
    func hideTaunt(author: String, date: String) async throws

    // Tables
    func profile() async throws -> Profile
    func updateProfile(_ patch: ProfilePatch) async throws
    /// Migration 0009: uploads a JPEG (≤ 1 MB, already resized by the caller) to the public
    /// `avatars` bucket at `<my id>.jpg`, then bumps `users.avatar_version` to `current + 1`
    /// and returns the new version. `avatarURL(userId:version:)` builds the display URL.
    func uploadAvatar(jpeg: Data, currentVersion: Int) async throws -> Int
    func myCircles() async throws -> [Circle]
    func createCircle(name: String) async throws -> Circle
    func leaveCircle(id: String) async throws
    func reactions(date: String) async throws -> [Reaction]
    func react(to userId: String, date: String, emoji: String) async throws
    func unreact(to userId: String, date: String) async throws
    func taunts(date: String) async throws -> [Taunt]
    func setTaunt(date: String, text: String) async throws
    func myResults(sinceDate: String) async throws -> [ResultSummary]
    func registerDevice(apnsToken: String, env: String) async throws
    /// Values and facts for the five items of a puzzle the caller has already played (RLS gates it). Returned in the order of `itemIds`.
    func reveal(itemIds: [Int]) async throws -> [RevealItem]
}

public extension KithAPI {
    /// Lineup board, for call sites written before the games hub.
    func board(kind: BoardKind, scopeId: String?, period: BoardPeriod, date: String) async throws -> [BoardRow] {
        try await board(kind: kind, scopeId: scopeId, period: period, date: date, game: .lineup)
    }
}

/// Partial update of the caller's `users` row. Only non-nil fields are sent.
public struct ProfilePatch: Codable, Sendable, Equatable {
    public var display_name: String?
    public var tz: String?
    public var discoverable: Bool?
    public var last_open_at: String?
    public var push_daily: Bool?
    public var push_daily_at: String?
    public var push_streak: Bool?
    public var push_passed: Bool?
    /// Migration 0009; set by `uploadAvatar`, never by hand.
    public var avatar_version: Int?
    public init(display_name: String? = nil, tz: String? = nil, discoverable: Bool? = nil,
                last_open_at: String? = nil, push_daily: Bool? = nil, push_daily_at: String? = nil,
                push_streak: Bool? = nil, push_passed: Bool? = nil, avatar_version: Int? = nil) {
        self.display_name = display_name; self.tz = tz; self.discoverable = discoverable
        self.last_open_at = last_open_at; self.push_daily = push_daily; self.push_daily_at = push_daily_at
        self.push_streak = push_streak; self.push_passed = push_passed; self.avatar_version = avatar_version
    }
}

/// Real implementation.
///
/// Request rules (all methods):
/// - Headers: `apikey: <anonKey>`, `Authorization: Bearer <token from AuthTokenProvider>`,
///   `Content-Type: application/json`; PostgREST writes add `Prefer: return=representation`
///   (inserts that need the row back) or `Prefer: return=minimal` (updates/deletes).
///   Missing token → throw `KithError.notSignedIn` before any request.
/// - Edge functions: POST `<baseURL>/functions/v1/<name>` with a JSON body.
/// - RPC: POST `<baseURL>/rest/v1/rpc/<name>` with a JSON object of named args.
/// - Tables: `<baseURL>/rest/v1/<table>?<PostgREST filters>`; e.g. `results?select=puzzle_date,tries,solved,score&puzzle_date=gte.<d>&order=puzzle_date.asc`.
///   The caller's own rows are selected by the server's RLS, so no `user_id=eq.` filter is needed
///   except where a table mixes visible users (reactions/taunts: filter by `puzzle_date=eq.<d>` only).
/// - Response mapping: 2xx → decode; 4xx → try to decode `APIErrorBody` (edge functions) or
///   PostgREST's `{"code","message"}` and throw `KithError.api(status, code, message)`;
///   transport errors → `KithError.network(description)`; decode failures → `KithError.decoding`.
/// - JSON decoding uses `JSONDecoder()` with default keys (models already use the wire names).
/// Specific calls:
/// - `joinCircle` returns the uuid string the RPC returns (PostgREST wraps a scalar as a bare JSON string).
/// - `board` passes `{ "kind", "scope_id" (null when nil), "period", "for_date" }`.
/// - `createCircle` inserts `{ "name", "owner_id": <current user id from the JWT `sub` claim> }` and returns the row;
///   decode the `sub` claim by base64url-decoding the JWT payload (no signature check needed client-side).
/// - `leaveCircle` deletes `circle_members?circle_id=eq.<id>&user_id=eq.<me>`.
/// - `react` upserts `reactions` with `Prefer: resolution=merge-duplicates,return=minimal`; `unreact` deletes by `from_user=eq.<me>&to_user=eq.<id>&puzzle_date=eq.<d>`.
/// - `setTaunt` inserts `taunts` (write-once; a 409 surfaces as `KithError.api`).
/// - `registerDevice` upserts `devices` `{ user_id, apns_token, env }` with merge-duplicates.
/// - `updateProfile` PATCHes `users?id=eq.<me>` with only the non-nil fields of the patch.
/// - `track` calls RPC `track` with `{ "p_name", "p_props" }` and ignores the empty response.
/// - `profile` GETs `users?select=id,display_name,tz,discoverable,invite_code,push_daily,push_daily_at,push_streak,push_passed&id=eq.<me>`
///   with `Accept: application/vnd.pgrst.object+json`, so PostgREST returns the single row as a JSON
///   object rather than a one-element array. No row (a signed-in user who has not registered) is a
///   406 with `{"code":"PGRST116",...}`, which maps to `KithError.api(status: 406, code: "PGRST116", ...)`.
/// - `reveal` GETs `list_items?select=id,label,value,fact&id=in.(<itemIds joined by ",">)` and reorders the
///   decoded rows to match `itemIds`, dropping ids the server did not return (RLS hides unplayed puzzles).
public final class SupabaseKithAPI: KithAPI {
    public let baseURL: URL
    public let anonKey: String
    private let http: HTTPClient
    private let auth: AuthTokenProvider

    public init(baseURL: URL, anonKey: String, http: HTTPClient, auth: AuthTokenProvider) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.http = http
        self.auth = auth
    }

    /// The `sub` claim of a JWT (user id) without verifying the signature. Nil if the token is malformed.
    public static func userId(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        guard let data = base64URLDecode(String(parts[1])) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["sub"] as? String
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    // MARK: Edge functions

    public func register(displayName: String, tz: String) async throws -> RegisterResponse {
        let token = try await requireToken()
        struct Body: Encodable { let displayName: String; let tz: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "functions/v1/register"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(displayName: displayName, tz: tz))
        )
        return try await send(request)
    }

    public func submitResult(puzzleDate: String, tz: String, attempts: [Attempt]) async throws -> SubmitResponse {
        let token = try await requireToken()
        struct Body: Encodable { let puzzleDate: String; let tz: String; let attempts: [Attempt] }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "functions/v1/submit-result"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(puzzleDate: puzzleDate, tz: tz, attempts: attempts))
        )
        return try await send(request)
    }

    public func matchContacts(added: [String], removed: [String], full: Bool) async throws -> MatchResponse {
        let token = try await requireToken()
        struct Body: Encodable { let added: [String]; let removed: [String]; let full: Bool }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "functions/v1/match-contacts"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(added: added, removed: removed, full: full))
        )
        return try await send(request)
    }

    public func deleteAccount() async throws {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .post,
            url: url(path: "functions/v1/delete-account"),
            headers: baseHeaders(token: token),
            body: Data("{}".utf8)
        )
        try await sendEmpty(request)
    }

    // MARK: RPCs

    public func startPuzzle(date: String) async throws -> Puzzle {
        let token = try await requireToken()
        struct Body: Encodable { let d: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/start_puzzle"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(d: date))
        )
        return try await send(request)
    }

    public func board(kind: BoardKind, scopeId: String?, period: BoardPeriod, date: String, game: BoardGame) async throws -> [BoardRow] {
        let token = try await requireToken()
        struct Body: Encodable {
            let kind: String
            let scope_id: String?
            let period: String
            let for_date: String
            let game_kind: String

            private enum CodingKeys: String, CodingKey {
                case kind, scope_id, period, for_date, game_kind
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(kind, forKey: .kind)
                if let scope_id {
                    try container.encode(scope_id, forKey: .scope_id)
                } else {
                    try container.encodeNil(forKey: .scope_id)
                }
                try container.encode(period, forKey: .period)
                try container.encode(for_date, forKey: .for_date)
                try container.encode(game_kind, forKey: .game_kind)
            }
        }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/board"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(kind: kind.rawValue, scope_id: scopeId, period: period.rawValue, for_date: date, game_kind: game.rawValue))
        )
        return try await send(request)
    }

    public func joinCircle(code: String) async throws -> String {
        let token = try await requireToken()
        struct Body: Encodable { let join_code: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/join_circle"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(join_code: code))
        )
        return try await send(request)
    }

    public func myStreak() async throws -> Int {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/my_streak"),
            headers: baseHeaders(token: token),
            body: Data("{}".utf8)
        )
        return try await send(request)
    }

    public func track(_ name: String, props: [String: String]) async throws {
        let token = try await requireToken()
        struct Body: Encodable { let p_name: String; let p_props: [String: String] }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/track"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(p_name: name, p_props: props))
        )
        try await sendEmpty(request)
    }

    public func hideTaunt(author: String, date: String) async throws {
        let token = try await requireToken()
        struct Body: Encodable { let author: String; let d: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/hide_taunt"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(author: author, d: date))
        )
        try await sendEmpty(request)
    }

    // MARK: Tables

    public func profile() async throws -> Profile {
        let token = try await requireToken()
        let me = try meId(from: token)
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/users", queryItems: [
                URLQueryItem(name: "select", value: Self.profileSelect),
                URLQueryItem(name: "id", value: "eq.\(me)"),
            ]),
            headers: baseHeaders(token: token, extra: ["Accept": "application/vnd.pgrst.object+json"])
        )
        return try await send(request)
    }

    /// The client-readable columns of the caller's `users` row, in `Profile`'s field order.
    private static let profileSelect =
        "id,display_name,tz,discoverable,invite_code,push_daily,push_daily_at,push_streak,push_passed,avatar_version"

    public func updateProfile(_ patch: ProfilePatch) async throws {
        let token = try await requireToken()
        let me = try meId(from: token)
        let request = try HTTPRequest(
            method: .patch,
            url: url(path: "rest/v1/users", queryItems: [URLQueryItem(name: "id", value: "eq.\(me)")]),
            headers: baseHeaders(token: token, extra: ["Prefer": "return=minimal"]),
            body: JSONEncoder().encode(patch)
        )
        try await sendEmpty(request)
    }

    public func uploadAvatar(jpeg: Data, currentVersion: Int) async throws -> Int {
        let token = try await requireToken()
        let me = try meId(from: token)
        // Storage REST: POST creates, and `x-upsert: true` lets the same path be replaced.
        let upload = HTTPRequest(
            method: .post,
            url: url(path: "storage/v1/object/avatars/\(me).jpg"),
            headers: baseHeaders(token: token, extra: [
                "Content-Type": "image/jpeg",
                "x-upsert": "true",
                "Cache-Control": "max-age=3600",
            ]),
            body: jpeg
        )
        try await sendEmpty(upload)
        let version = currentVersion + 1
        try await updateProfile(ProfilePatch(avatar_version: version))
        return version
    }

    /// Public URL of a user's picture, or nil when they have none (`version` 0 / nil). The
    /// version rides along as a query item purely to defeat image caches after an upload.
    public func avatarURL(userId: String, version: Int?) -> URL? {
        guard let version, version > 0 else { return nil }
        return url(path: "storage/v1/object/public/avatars/\(userId).jpg",
                   queryItems: [URLQueryItem(name: "v", value: String(version))])
    }

    public func myCircles() async throws -> [Circle] {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/circles"),
            headers: baseHeaders(token: token)
        )
        return try await send(request)
    }

    public func createCircle(name: String) async throws -> Circle {
        let token = try await requireToken()
        let me = try meId(from: token)
        struct Body: Encodable { let name: String; let owner_id: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/circles"),
            headers: baseHeaders(token: token, extra: ["Prefer": "return=representation"]),
            body: JSONEncoder().encode(Body(name: name, owner_id: me))
        )
        let rows: [Circle] = try await send(request)
        guard let circle = rows.first else {
            throw KithError.decoding("circle row not returned")
        }
        return circle
    }

    public func leaveCircle(id: String) async throws {
        let token = try await requireToken()
        let me = try meId(from: token)
        let request = HTTPRequest(
            method: .delete,
            url: url(path: "rest/v1/circle_members", queryItems: [
                URLQueryItem(name: "circle_id", value: "eq.\(id)"),
                URLQueryItem(name: "user_id", value: "eq.\(me)"),
            ]),
            headers: baseHeaders(token: token, extra: ["Prefer": "return=minimal"])
        )
        try await sendEmpty(request)
    }

    public func reactions(date: String) async throws -> [Reaction] {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/reactions", queryItems: [URLQueryItem(name: "puzzle_date", value: "eq.\(date)")]),
            headers: baseHeaders(token: token)
        )
        return try await send(request)
    }

    public func react(to userId: String, date: String, emoji: String) async throws {
        let token = try await requireToken()
        let me = try meId(from: token)
        struct Body: Encodable { let from_user: String; let to_user: String; let puzzle_date: String; let emoji: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/reactions"),
            headers: baseHeaders(token: token, extra: ["Prefer": "resolution=merge-duplicates,return=minimal"]),
            body: JSONEncoder().encode(Body(from_user: me, to_user: userId, puzzle_date: date, emoji: emoji))
        )
        try await sendEmpty(request)
    }

    public func unreact(to userId: String, date: String) async throws {
        let token = try await requireToken()
        let me = try meId(from: token)
        let request = HTTPRequest(
            method: .delete,
            url: url(path: "rest/v1/reactions", queryItems: [
                URLQueryItem(name: "from_user", value: "eq.\(me)"),
                URLQueryItem(name: "to_user", value: "eq.\(userId)"),
                URLQueryItem(name: "puzzle_date", value: "eq.\(date)"),
            ]),
            headers: baseHeaders(token: token, extra: ["Prefer": "return=minimal"])
        )
        try await sendEmpty(request)
    }

    public func taunts(date: String) async throws -> [Taunt] {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/taunts", queryItems: [URLQueryItem(name: "puzzle_date", value: "eq.\(date)")]),
            headers: baseHeaders(token: token)
        )
        return try await send(request)
    }

    public func setTaunt(date: String, text: String) async throws {
        let token = try await requireToken()
        let me = try meId(from: token)
        struct Body: Encodable { let user_id: String; let puzzle_date: String; let text: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/taunts"),
            headers: baseHeaders(token: token, extra: ["Prefer": "return=minimal"]),
            body: JSONEncoder().encode(Body(user_id: me, puzzle_date: date, text: text))
        )
        try await sendEmpty(request)
    }

    public func myResults(sinceDate: String) async throws -> [ResultSummary] {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/results", queryItems: [
                URLQueryItem(name: "select", value: "puzzle_date,tries,solved,score"),
                URLQueryItem(name: "puzzle_date", value: "gte.\(sinceDate)"),
                URLQueryItem(name: "order", value: "puzzle_date.asc"),
            ]),
            headers: baseHeaders(token: token)
        )
        return try await send(request)
    }

    public func registerDevice(apnsToken: String, env: String) async throws {
        let token = try await requireToken()
        let me = try meId(from: token)
        struct Body: Encodable { let user_id: String; let apns_token: String; let env: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/devices"),
            headers: baseHeaders(token: token, extra: ["Prefer": "resolution=merge-duplicates,return=minimal"]),
            body: JSONEncoder().encode(Body(user_id: me, apns_token: apnsToken, env: env))
        )
        try await sendEmpty(request)
    }

    public func reveal(itemIds: [Int]) async throws -> [RevealItem] {
        let token = try await requireToken()
        let list = itemIds.map(String.init).joined(separator: ",")
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/list_items", queryItems: [
                URLQueryItem(name: "select", value: "id,label,value,fact"),
                URLQueryItem(name: "id", value: "in.(\(list))"),
            ]),
            headers: baseHeaders(token: token)
        )
        let rows: [RevealItem] = try await send(request)
        // PostgREST returns rows in the table's order; the caller asked for `itemIds`' order.
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return itemIds.compactMap { byId[$0] }
    }

    // MARK: - Request plumbing

    private func requireToken() async throws -> String {
        guard let token = try await auth.accessToken() else {
            throw KithError.notSignedIn
        }
        return token
    }

    /// The caller's user id from the token's `sub` claim. Throws `KithError.notSignedIn` when
    /// the token has no readable `sub` claim (treated the same as not being signed in).
    private func meId(from token: String) throws -> String {
        guard let id = Self.userId(fromJWT: token) else {
            throw KithError.notSignedIn
        }
        return id
    }

    private func baseHeaders(token: String, extra: [String: String] = [:]) -> [String: String] {
        var headers: [String: String] = [
            "apikey": anonKey,
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
        ]
        for (key, value) in extra {
            headers[key] = value
        }
        return headers
    }

    private func url(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents(string: baseURL.absoluteString)!
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url ?? baseURL
    }

    /// PostgREST error shape.
    private struct PostgRESTErrorBody: Decodable {
        let code: String
        let message: String
    }

    private func errorFromBody(_ data: Data) -> (code: String, message: String)? {
        if let edgeError = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            return (edgeError.code, edgeError.error)
        }
        if let pgError = try? JSONDecoder().decode(PostgRESTErrorBody.self, from: data) {
            return (pgError.code, pgError.message)
        }
        return nil
    }

    private func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await http.send(request)
        } catch let error as KithError {
            throw error
        } catch {
            throw KithError.network(String(describing: error))
        }
    }

    private func send<T: Decodable>(_ request: HTTPRequest) async throws -> T {
        let response = try await perform(request)
        guard (200..<300).contains(response.status) else {
            if let (code, message) = errorFromBody(response.body) {
                throw KithError.api(status: response.status, code: code, message: message)
            }
            throw KithError.api(status: response.status, code: "unknown", message: "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw KithError.decoding(String(describing: error))
        }
    }

    private func sendEmpty(_ request: HTTPRequest) async throws {
        let response = try await perform(request)
        guard (200..<300).contains(response.status) else {
            if let (code, message) = errorFromBody(response.body) {
                throw KithError.api(status: response.status, code: code, message: message)
            }
            throw KithError.api(status: response.status, code: "unknown", message: "")
        }
    }
    // MARK: Games hub (docs/07) — bodies to implement

    public func startGame(date: String, game: GameKind) async throws -> StartedGame {
        let token = try await requireToken()
        struct Body: Encodable { let d: String; let g: String }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "rest/v1/rpc/start_game"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(d: date, g: game.rawValue))
        )
        return try await send(request)
    }

    public func submitGame(date: String, game: GameKind, tz: String, elapsedMs: Int, mistakes: Int,
                           gaveUp: Bool, answer: GameAnswer?) async throws -> SubmitGameResponse {
        let token = try await requireToken()
        struct Body: Encodable {
            let date: String
            let game: String
            let tz: String
            let elapsedMs: Int
            let mistakes: Int
            let gaveUp: Bool
            let answer: GameAnswer?

            private enum CodingKeys: String, CodingKey {
                case date, game, tz, elapsedMs, mistakes, gaveUp, answer
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(date, forKey: .date)
                try container.encode(game, forKey: .game)
                try container.encode(tz, forKey: .tz)
                try container.encode(elapsedMs, forKey: .elapsedMs)
                try container.encode(mistakes, forKey: .mistakes)
                try container.encode(gaveUp, forKey: .gaveUp)
                if let answer {
                    try container.encode(answer, forKey: .answer)
                }
            }
        }
        let request = try HTTPRequest(
            method: .post,
            url: url(path: "functions/v1/submit-game"),
            headers: baseHeaders(token: token),
            body: JSONEncoder().encode(Body(
                date: date, game: game.rawValue, tz: tz, elapsedMs: elapsedMs,
                mistakes: mistakes, gaveUp: gaveUp, answer: answer
            ))
        )
        return try await send(request)
    }

    public func myGameResults(sinceDate: String) async throws -> [GameResultSummary] {
        let token = try await requireToken()
        let me = try meId(from: token)
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/game_results", queryItems: [
                URLQueryItem(name: "select", value: "date,game,elapsed_ms,mistakes,solved,gave_up,score"),
                URLQueryItem(name: "user_id", value: "eq.\(me)"),
                URLQueryItem(name: "date", value: "gte.\(sinceDate)"),
                URLQueryItem(name: "order", value: "date.asc"),
            ]),
            headers: baseHeaders(token: token)
        )
        return try await send(request)
    }

    public func dailyGames(date: String) async throws -> [DailyGameRow] {
        let token = try await requireToken()
        let request = HTTPRequest(
            method: .get,
            url: url(path: "rest/v1/daily_games", queryItems: [
                URLQueryItem(name: "select", value: "date,game,number,difficulty"),
                URLQueryItem(name: "date", value: "eq.\(date)"),
                URLQueryItem(name: "order", value: "game.asc"),
            ]),
            headers: baseHeaders(token: token)
        )
        return try await send(request)
    }

}
