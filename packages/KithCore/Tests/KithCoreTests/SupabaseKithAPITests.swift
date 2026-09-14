import XCTest
@testable import KithCore
import GridGames
import LineupEngine

final class SupabaseKithAPITests: XCTestCase {
    private let baseURL = URL(string: "https://example.supabase.co")!
    private let anonKey = "anon-key-123"

    private func makeAPI(http: FakeHTTPClient, auth: FakeAuth) -> SupabaseKithAPI {
        SupabaseKithAPI(baseURL: baseURL, anonKey: anonKey, http: http, auth: auth)
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
    }

    // MARK: Missing token

    func testMissingTokenThrowsNotSignedInWithoutSendingARequest() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: nil))

        do {
            _ = try await api.profile()
            XCTFail("expected KithError.notSignedIn")
        } catch {
            XCTAssertEqual(error as? KithError, .notSignedIn)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    // MARK: register (edge function)

    func testRegisterSendsExpectedRequestAndDecodesTheResponse() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 201, body: Data("""
        {"userId":"u1","displayName":"Zed","inviteCode":"ABCD12","existing":false}
        """.utf8))

        let response = try await api.register(displayName: "Zed", tz: "America/New_York")

        XCTAssertEqual(response, RegisterResponse(userId: "u1", displayName: "Zed", inviteCode: "ABCD12", existing: false))

        XCTAssertEqual(http.requests.count, 1)
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("functions/v1/register"))
        XCTAssertEqual(req.headers["apikey"], anonKey)
        XCTAssertEqual(req.headers["Authorization"], "Bearer token-abc")
        XCTAssertEqual(req.headers["Content-Type"], "application/json")

        let body = try jsonObject(req.body)
        XCTAssertEqual(body["displayName"] as? String, "Zed")
        XCTAssertEqual(body["tz"] as? String, "America/New_York")
    }

    // MARK: startPuzzle (RPC)

    func testStartPuzzleSendsRPCBodyAndDecodesThePuzzle() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        {"date":"2026-09-11","number":142,"prompt":"Order these by year",
         "direction":"Earliest at the top",
         "items":[{"id":1,"label":"A"},{"id":2,"label":"B"},{"id":3,"label":"C"},{"id":4,"label":"D"},{"id":5,"label":"E"}],
         "correctOrder":[1,2,3,4,5]}
        """.utf8))

        let puzzle = try await api.startPuzzle(date: "2026-09-11")

        XCTAssertEqual(puzzle.date, "2026-09-11")
        XCTAssertEqual(puzzle.number, 142)
        XCTAssertEqual(puzzle.items.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(puzzle.correctOrder, [1, 2, 3, 4, 5])

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("rest/v1/rpc/start_puzzle"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["d"] as? String, "2026-09-11")
    }

    // MARK: board (RPC)

    func testBoardSendsRPCBodyWithNullScopeAndDecodesRowsIncludingNulls() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        [
          {"user_id":"u1","display_name":"A","score":900,"tries":1,"elapsed_ms":12000,"attempts":null,"played":true,"rank":1,"prev_rank":null},
          {"user_id":"u2","display_name":"B","score":0,"tries":null,"elapsed_ms":null,"attempts":null,"played":false,"rank":null,"prev_rank":null}
        ]
        """.utf8))

        let rows = try await api.board(kind: .friends, scopeId: nil, period: .today, date: "2026-09-11")

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].user_id, "u1")
        XCTAssertEqual(rows[0].rank, 1)
        XCTAssertNil(rows[0].prev_rank)
        XCTAssertEqual(rows[1].played, false)
        XCTAssertNil(rows[1].tries)
        XCTAssertNil(rows[1].rank)

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["kind"] as? String, "friends")
        XCTAssertTrue(body["scope_id"] is NSNull, "scope_id should be null, got \(String(describing: body["scope_id"]))")
        XCTAssertEqual(body["period"] as? String, "today")
        XCTAssertEqual(body["for_date"] as? String, "2026-09-11")
        XCTAssertEqual(body["game_kind"] as? String, "lineup")
    }

    func testBoardWithExplicitGameSendsThatGameKind() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("[]".utf8))

        _ = try await api.board(kind: .friends, scopeId: nil, period: .week, date: "2026-09-11", game: .total)

        let req = try XCTUnwrap(http.requests.first)
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["game_kind"] as? String, "total")
    }

    // MARK: joinCircle (RPC returning a bare scalar)

    func testJoinCircleDecodesABareJSONString() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data(#""11111111-2222-3333-4444-555555555555""#.utf8))

        let id = try await api.joinCircle(code: "ABCD12")

        XCTAssertEqual(id, "11111111-2222-3333-4444-555555555555")
        let body = try jsonObject(http.requests.first?.body)
        XCTAssertEqual(body["join_code"] as? String, "ABCD12")
    }

    // MARK: myResults (PostgREST GET with filters)

    func testMyResultsSendsAFilteredGETRequest() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("[]".utf8))

        let results = try await api.myResults(sinceDate: "2026-09-01")

        XCTAssertEqual(results, [])
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        let urlString = req.url.absoluteString
        XCTAssertTrue(urlString.hasPrefix("https://example.supabase.co/rest/v1/results?"))
        XCTAssertTrue(urlString.contains("select="))
        XCTAssertTrue(urlString.contains("puzzle_date=gte.2026-09-01"))
        XCTAssertTrue(urlString.contains("order=puzzle_date.asc"))
    }

    // MARK: updateProfile (PostgREST PATCH with only non-nil fields)

    func testUpdateProfilePatchesOnlyTheNonNilFields() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 200)

        try await api.updateProfile(ProfilePatch(display_name: "New Name", push_daily: true))

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .patch)
        XCTAssertEqual(req.url, URL(string: "https://example.supabase.co/rest/v1/users?id=eq.user-42")!)
        let body = try jsonObject(req.body)
        XCTAssertEqual(body.count, 2)
        XCTAssertEqual(body["display_name"] as? String, "New Name")
        XCTAssertEqual(body["push_daily"] as? Bool, true)
    }

    // MARK: react (PostgREST upsert with merge-duplicates)

    func testReactUpsertsWithMergeDuplicatesPreferHeader() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 201)

        try await api.react(to: "friend-1", date: "2026-09-11", emoji: "🔥")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url.path, "/rest/v1/reactions")
        let prefer = try XCTUnwrap(req.headers["Prefer"])
        XCTAssertTrue(prefer.contains("merge-duplicates"), "Prefer header was \(prefer)")

        let body = try jsonObject(req.body)
        XCTAssertEqual(body["from_user"] as? String, "user-42")
        XCTAssertEqual(body["to_user"] as? String, "friend-1")
        XCTAssertEqual(body["puzzle_date"] as? String, "2026-09-11")
        XCTAssertEqual(body["emoji"] as? String, "🔥")
    }

    // MARK: unreact (PostgREST DELETE with three filters)

    func testUnreactSendsDeleteWithTheThreeFilters() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 200)

        try await api.unreact(to: "friend-1", date: "2026-09-11")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .delete)
        let urlString = req.url.absoluteString
        XCTAssertTrue(urlString.hasPrefix("https://example.supabase.co/rest/v1/reactions?"))
        XCTAssertTrue(urlString.contains("from_user=eq.user-42"))
        XCTAssertTrue(urlString.contains("to_user=eq.friend-1"))
        XCTAssertTrue(urlString.contains("puzzle_date=eq.2026-09-11"))
    }

    // MARK: createCircle (owner_id from the JWT sub claim)

    func testCreateCircleInsertsWithOwnerIdFromJWTAndReturnsRepresentation() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 201, body: Data("""
        [{"id":"c1","code":"ABC123","name":"My Circle","owner_id":"user-42"}]
        """.utf8))

        let circle = try await api.createCircle(name: "My Circle")

        XCTAssertEqual(circle, Circle(id: "c1", code: "ABC123", name: "My Circle", owner_id: "user-42"))

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url.path, "/rest/v1/circles")
        let prefer = try XCTUnwrap(req.headers["Prefer"])
        XCTAssertTrue(prefer.contains("return=representation"), "Prefer header was \(prefer)")

        let body = try jsonObject(req.body)
        XCTAssertEqual(body["name"] as? String, "My Circle")
        XCTAssertEqual(body["owner_id"] as? String, "user-42")
    }

    // MARK: Error mapping

    func testEdgeFunctionErrorBodyMapsToKithErrorAPI() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 409, body: Data("""
        {"error":"already played","code":"already_played"}
        """.utf8))

        do {
            _ = try await api.register(displayName: "Zed", tz: "UTC")
            XCTFail("expected KithError.api")
        } catch {
            guard case .api(let status, let code, _) = error as? KithError else {
                return XCTFail("expected KithError.api, got \(error)")
            }
            XCTAssertEqual(status, 409)
            XCTAssertEqual(code, "already_played")
        }
    }

    func testPostgRESTErrorBodyMapsToKithErrorAPI() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "11111111-1111-1111-1111-111111111111")))
        http.queue(status: 400, body: Data("""
        {"code":"22P02","message":"invalid input"}
        """.utf8))

        do {
            _ = try await api.profile()
            XCTFail("expected KithError.api")
        } catch {
            guard case .api(let status, let code, let message) = error as? KithError else {
                return XCTFail("expected KithError.api, got \(error)")
            }
            XCTAssertEqual(status, 400)
            XCTAssertEqual(code, "22P02")
            XCTAssertEqual(message, "invalid input")
        }
    }

    func testTransportThrowMapsToKithErrorNetwork() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "11111111-1111-1111-1111-111111111111")))
        http.queue(throwing: DummyTransportError())

        do {
            _ = try await api.profile()
            XCTFail("expected KithError.network")
        } catch {
            guard case .network = error as? KithError else {
                return XCTFail("expected KithError.network, got \(error)")
            }
        }
    }

    func testMalformedJSONOn200MapsToKithErrorDecoding() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "11111111-1111-1111-1111-111111111111")))
        http.queue(status: 200, body: Data("not json".utf8))

        do {
            _ = try await api.profile()
            XCTFail("expected KithError.decoding")
        } catch {
            guard case .decoding = error as? KithError else {
                return XCTFail("expected KithError.decoding, got \(error)")
            }
        }
    }

    func testTokenWithoutSubMapsToNotSignedIn() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))

        do {
            _ = try await api.profile()
            XCTFail("expected KithError.notSignedIn")
        } catch {
            XCTAssertEqual(error as? KithError, .notSignedIn)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    // MARK: profile (single-object Accept header + explicit select)

    func testProfileSendsTheSelectAndObjectAcceptHeaderAndDecodesOneObject() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 200, body: Data("""
        {"id":"user-42","display_name":"Zed","tz":"America/New_York","discoverable":true,
         "invite_code":"ABCD12","push_daily":true,"push_daily_at":"08:00:00",
         "push_streak":false,"push_passed":true}
        """.utf8))

        let profile = try await api.profile()

        XCTAssertEqual(profile.id, "user-42")
        XCTAssertEqual(profile.display_name, "Zed")
        XCTAssertEqual(profile.invite_code, "ABCD12")
        XCTAssertEqual(profile.push_daily_at, "08:00:00")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(
            req.url.absoluteString,
            "https://example.supabase.co/rest/v1/users?"
                + "select=id,display_name,tz,discoverable,invite_code,push_daily,push_daily_at,push_streak,push_passed,avatar_version"
                + "&id=eq.user-42"
        )
        XCTAssertEqual(req.headers["Accept"], "application/vnd.pgrst.object+json")
        XCTAssertNil(req.body)
    }

    func testProfile406WithPGRST116MapsToKithErrorAPI() async {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 406, body: Data("""
        {"code":"PGRST116","message":"JSON object requested, multiple (or no) rows returned"}
        """.utf8))

        do {
            _ = try await api.profile()
            XCTFail("expected KithError.api")
        } catch {
            guard case .api(let status, let code, let message) = error as? KithError else {
                return XCTFail("expected KithError.api, got \(error)")
            }
            XCTAssertEqual(status, 406)
            XCTAssertEqual(code, "PGRST116")
            XCTAssertEqual(message, "JSON object requested, multiple (or no) rows returned")
        }
        // The select must be on the request even on the failure path.
        XCTAssertTrue(
            http.requests.first?.url.absoluteString.contains(
                "select=id,display_name,tz,discoverable,invite_code,push_daily,push_daily_at,push_streak,push_passed,avatar_version"
            ) == true,
            "URL was \(String(describing: http.requests.first?.url))"
        )
    }

    // MARK: reveal (PostgREST GET with an `in.(...)` filter, reordered client-side)

    func testRevealSendsTheInFilterAndReordersRowsToMatchItemIds() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        // Server order (table order) differs from the requested order, and id 5 is absent.
        http.queue(status: 200, body: Data("""
        [
          {"id":1,"label":"Bicycle","value":1817,"fact":"The first version had no pedals"},
          {"id":2,"label":"Telephone","value":1876,"fact":null},
          {"id":3,"label":"Radio","value":1895,"fact":"Marconi's first patent"},
          {"id":4,"label":"Television","value":1927,"fact":null}
        ]
        """.utf8))

        let items = try await api.reveal(itemIds: [3, 1, 5, 4, 2])

        XCTAssertEqual(items.map(\.id), [3, 1, 4, 2], "unreturned ids are dropped, the rest keep the asked-for order")
        XCTAssertEqual(items.first, RevealItem(id: 3, label: "Radio", value: 1895, fact: "Marconi's first patent"))
        XCTAssertNil(items.last?.fact)

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(
            req.url.absoluteString,
            "https://example.supabase.co/rest/v1/list_items?select=id,label,value,fact&id=in.(3,1,5,4,2)"
        )
        XCTAssertEqual(req.headers["apikey"], anonKey)
        XCTAssertEqual(req.headers["Authorization"], "Bearer token-abc")
        XCTAssertNil(req.body)
    }

    // MARK: submitResult (edge function)

    func testSubmitResultPostsTheAttemptsAndDecodesTheStoredResult() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        {"result":{"puzzleDate":"2026-09-11","tries":2,"solved":true,"elapsedMs":48000,"score":520,
                   "attempts":[{"order":[1,2,3,4,5],"feedback":["correct","correct","correct","correct","correct"],"elapsedMs":48000}],
                   "elapsedSource":"client","submittedAt":"2026-09-11T12:00:00Z"},
         "streak":12}
        """.utf8))

        let attempt = Attempt(
            order: [1, 2, 3, 4, 5],
            feedback: [.correct, .correct, .correct, .correct, .correct],
            elapsedMs: 48_000
        )
        let response = try await api.submitResult(puzzleDate: "2026-09-11", tz: "Europe/London", attempts: [attempt])

        XCTAssertEqual(response.streak, 12)
        XCTAssertEqual(response.result.score, 520)

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("functions/v1/submit-result"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["puzzleDate"] as? String, "2026-09-11")
        XCTAssertEqual(body["tz"] as? String, "Europe/London")
        let attempts = try XCTUnwrap(body["attempts"] as? [[String: Any]])
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0]["order"] as? [Int], [1, 2, 3, 4, 5])
        XCTAssertEqual(attempts[0]["elapsedMs"] as? Int, 48_000)
    }

    // MARK: matchContacts (edge function)

    func testMatchContactsPostsTheDiffAndDecodesMatchesAndFriends() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        {"matches":[{"userId":"u1","displayName":"Bob","hash":"h1"}],
         "friends":[{"userId":"u1","displayName":"Bob"}],
         "stored":3}
        """.utf8))

        let response = try await api.matchContacts(added: ["h1", "h2"], removed: ["h3"], full: false)

        XCTAssertEqual(response.stored, 3)
        XCTAssertEqual(response.matches, [MatchedContact(userId: "u1", displayName: "Bob", hash: "h1")])
        XCTAssertEqual(response.friends, [Friend(userId: "u1", displayName: "Bob")])

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("functions/v1/match-contacts"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["added"] as? [String], ["h1", "h2"])
        XCTAssertEqual(body["removed"] as? [String], ["h3"])
        XCTAssertEqual(body["full"] as? Bool, false)
    }

    // MARK: deleteAccount (edge function, empty body)

    func testDeleteAccountPostsAnEmptyJSONObject() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 204)

        try await api.deleteAccount()

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("functions/v1/delete-account"))
        XCTAssertEqual(req.headers["Authorization"], "Bearer token-abc")
        XCTAssertEqual(try jsonObject(req.body).count, 0)
    }

    // MARK: myStreak (RPC returning a bare scalar)

    func testMyStreakPostsAnEmptyBodyAndDecodesABareInt() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("12".utf8))

        let streak = try await api.myStreak()

        XCTAssertEqual(streak, 12)
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("rest/v1/rpc/my_streak"))
        XCTAssertEqual(try jsonObject(req.body).count, 0)
    }

    // MARK: track (RPC, empty response)

    func testTrackPostsTheNameAndPropsToTheRPC() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 204)

        try await api.track("puzzle_submit", props: ["date": "2026-09-11"])

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("rest/v1/rpc/track"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["p_name"] as? String, "puzzle_submit")
        XCTAssertEqual(body["p_props"] as? [String: String], ["date": "2026-09-11"])
    }

    // MARK: hideTaunt (RPC)

    func testHideTauntPostsTheAuthorAndDate() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 204)

        try await api.hideTaunt(author: "friend-1", date: "2026-09-11")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("rest/v1/rpc/hide_taunt"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["author"] as? String, "friend-1")
        XCTAssertEqual(body["d"] as? String, "2026-09-11")
    }

    // MARK: myCircles (PostgREST GET, RLS-scoped, no filters)

    func testMyCirclesSendsAnUnfilteredGETAndDecodesTheRows() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        [{"id":"c1","code":"ABC123","name":"Work","owner_id":"user-42"}]
        """.utf8))

        let circles = try await api.myCircles()

        XCTAssertEqual(circles, [Circle(id: "c1", code: "ABC123", name: "Work", owner_id: "user-42")])
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(req.url.absoluteString, "https://example.supabase.co/rest/v1/circles")
        XCTAssertNil(req.body)
    }

    // MARK: leaveCircle (PostgREST DELETE on the join table)

    func testLeaveCircleDeletesTheMembershipRowForMe() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 204)

        try await api.leaveCircle(id: "c1")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .delete)
        XCTAssertEqual(
            req.url.absoluteString,
            "https://example.supabase.co/rest/v1/circle_members?circle_id=eq.c1&user_id=eq.user-42"
        )
        XCTAssertEqual(req.headers["Prefer"], "return=minimal")
    }

    // MARK: reactions / taunts (PostgREST GET filtered by date only)

    func testReactionsFiltersByPuzzleDateOnly() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        [{"from_user":"user-42","to_user":"friend-1","puzzle_date":"2026-09-11","emoji":"🔥"}]
        """.utf8))

        let reactions = try await api.reactions(date: "2026-09-11")

        XCTAssertEqual(reactions.count, 1)
        XCTAssertEqual(reactions[0].emoji, "🔥")
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(
            req.url.absoluteString,
            "https://example.supabase.co/rest/v1/reactions?puzzle_date=eq.2026-09-11"
        )
    }

    func testTauntsFiltersByPuzzleDateOnly() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        [{"user_id":"friend-1","puzzle_date":"2026-09-11","text":"easy"}]
        """.utf8))

        let taunts = try await api.taunts(date: "2026-09-11")

        XCTAssertEqual(taunts, [Taunt(user_id: "friend-1", puzzle_date: "2026-09-11", text: "easy")])
        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(
            req.url.absoluteString,
            "https://example.supabase.co/rest/v1/taunts?puzzle_date=eq.2026-09-11"
        )
    }

    // MARK: setTaunt (write-once insert)

    func testSetTauntInsertsWithTheCallersIdAndMinimalReturn() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 201)

        try await api.setTaunt(date: "2026-09-11", text: "get wrecked")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url.absoluteString, "https://example.supabase.co/rest/v1/taunts")
        XCTAssertEqual(req.headers["Prefer"], "return=minimal")
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["user_id"] as? String, "user-42")
        XCTAssertEqual(body["puzzle_date"] as? String, "2026-09-11")
        XCTAssertEqual(body["text"] as? String, "get wrecked")
    }

    // MARK: registerDevice (upsert)

    func testRegisterDeviceUpsertsTheTokenWithMergeDuplicates() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 201)

        try await api.registerDevice(apnsToken: "deadbeef", env: "sandbox")

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url.absoluteString, "https://example.supabase.co/rest/v1/devices")
        let prefer = try XCTUnwrap(req.headers["Prefer"])
        XCTAssertTrue(prefer.contains("merge-duplicates"), "Prefer header was \(prefer)")
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["user_id"] as? String, "user-42")
        XCTAssertEqual(body["apns_token"] as? String, "deadbeef")
        XCTAssertEqual(body["env"] as? String, "sandbox")
    }

    // MARK: userId(fromJWT:)

    func testUserIdFromJWTHappyPath() {
        XCTAssertEqual(SupabaseKithAPI.userId(fromJWT: makeJWT(sub: "user-99")), "user-99")
    }

    func testUserIdFromJWTMalformedReturnsNil() {
        XCTAssertNil(SupabaseKithAPI.userId(fromJWT: "not-a-jwt"))
        XCTAssertNil(SupabaseKithAPI.userId(fromJWT: "only.two-parts"))
        XCTAssertNil(SupabaseKithAPI.userId(fromJWT: "not base64!.not base64!.sig"))
    }

    // MARK: startGame (RPC)

    func testStartGameSendsRPCBodyAndDecodesTheStartedGame() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        {"date":"2026-09-11","game":"stars","number":12,"difficulty":"medium",
         "spec":{"n":2,"regions":[[0,1],[1,0]]}}
        """.utf8))

        let started = try await api.startGame(date: "2026-09-11", game: .stars)

        XCTAssertEqual(started.date, "2026-09-11")
        XCTAssertEqual(started.game, .stars)
        XCTAssertEqual(started.number, 12)
        XCTAssertEqual(started.spec, .stars(StarsSpec(n: 2, regions: [[0, 1], [1, 0]])))

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("rest/v1/rpc/start_game"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["d"] as? String, "2026-09-11")
        XCTAssertEqual(body["g"] as? String, "stars")
    }

    // MARK: submitGame (edge function)

    func testSubmitGamePostsTheAnswerAndDecodesTheResponse() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        {"result":{"date":"2026-09-11","game":"stars","elapsedMs":48000,"elapsedSource":"client",
                   "mistakes":1,"solved":true,"gaveUp":false,"score":904,"submittedAt":"2026-09-11T12:00:00Z"},
         "streak":5}
        """.utf8))

        let response = try await api.submitGame(
            date: "2026-09-11", game: .stars, tz: "Europe/London",
            elapsedMs: 48_000, mistakes: 1, gaveUp: false, answer: .stars([0, 1])
        )

        XCTAssertEqual(response.streak, 5)
        XCTAssertEqual(response.result.score, 904)

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.url, baseURL.appendingPathComponent("functions/v1/submit-game"))
        let body = try jsonObject(req.body)
        XCTAssertEqual(body["date"] as? String, "2026-09-11")
        XCTAssertEqual(body["game"] as? String, "stars")
        XCTAssertEqual(body["tz"] as? String, "Europe/London")
        XCTAssertEqual(body["elapsedMs"] as? Int, 48_000)
        XCTAssertEqual(body["mistakes"] as? Int, 1)
        XCTAssertEqual(body["gaveUp"] as? Bool, false)
        let answer = try XCTUnwrap(body["answer"] as? [String: Any])
        XCTAssertEqual(answer["stars"] as? [Int], [0, 1])
    }

    func testSubmitGameOmitsAnswerKeyWhenNil() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        {"result":{"date":"2026-09-11","game":"trail","elapsedMs":10000,"elapsedSource":"client",
                   "mistakes":0,"solved":false,"gaveUp":true,"score":100,"submittedAt":"2026-09-11T12:00:00Z"},
         "streak":0}
        """.utf8))

        _ = try await api.submitGame(
            date: "2026-09-11", game: .trail, tz: "UTC",
            elapsedMs: 10_000, mistakes: 0, gaveUp: true, answer: nil
        )

        let req = try XCTUnwrap(http.requests.first)
        let body = try jsonObject(req.body)
        XCTAssertFalse(body.keys.contains("answer"), "answer key should be omitted when nil, got \(body)")
    }

    // MARK: myGameResults (PostgREST GET)

    func testMyGameResultsSendsFilteredGETAndDecodesSnakeCaseFields() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: makeJWT(sub: "user-42")))
        http.queue(status: 200, body: Data("""
        [{"date":"2026-09-11","game":"duo","elapsed_ms":30000,"mistakes":2,"solved":true,"gave_up":false,"score":940}]
        """.utf8))

        let results = try await api.myGameResults(sinceDate: "2026-09-01")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].elapsed_ms, 30_000)
        XCTAssertEqual(results[0].gave_up, false)
        XCTAssertEqual(results[0].solved, true)

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        let urlString = req.url.absoluteString
        XCTAssertTrue(urlString.hasPrefix("https://example.supabase.co/rest/v1/game_results?"))
        XCTAssertTrue(urlString.contains("select=date,game,elapsed_ms,mistakes,solved,gave_up,score"))
        XCTAssertTrue(urlString.contains("user_id=eq.user-42"))
        XCTAssertTrue(urlString.contains("date=gte.2026-09-01"))
        XCTAssertTrue(urlString.contains("order=date.asc"))
    }

    // MARK: dailyGames (PostgREST GET)

    func testDailyGamesSendsFilteredGETAndDecodesRows() async throws {
        let http = FakeHTTPClient()
        let api = makeAPI(http: http, auth: FakeAuth(token: "token-abc"))
        http.queue(status: 200, body: Data("""
        [{"date":"2026-09-11","game":"duo","number":4,"difficulty":"easy"}]
        """.utf8))

        let rows = try await api.dailyGames(date: "2026-09-11")

        XCTAssertEqual(rows, [DailyGameRow(date: "2026-09-11", game: .duo, number: 4, difficulty: "easy")])

        let req = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(
            req.url.absoluteString,
            "https://example.supabase.co/rest/v1/daily_games?select=date,game,number,difficulty&date=eq.2026-09-11&order=game.asc"
        )
    }
}
