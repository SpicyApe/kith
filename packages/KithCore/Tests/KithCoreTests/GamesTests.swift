// GamesTests.swift — StartedGame decoding and GameAnswer encoding (docs/07-games-hub.md).

import XCTest
@testable import KithCore
import GridGames

final class GamesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: StartedGame — spec decodes to match `game`

    func testStartedGameDecodesStarsSpec() throws {
        let started = try decode(StartedGame.self, """
        {"date":"2026-09-11","game":"stars","number":12,"difficulty":"medium",
         "spec":{"n":3,"regions":[[0,1,2],[1,2,0],[2,0,1]]}}
        """)
        XCTAssertEqual(started.spec, .stars(StarsSpec(n: 3, regions: [[0, 1, 2], [1, 2, 0], [2, 0, 1]])))
        XCTAssertEqual(started.spec.kind, .stars)
    }

    func testStartedGameDecodesDuoSpec() throws {
        let started = try decode(StartedGame.self, """
        {"date":"2026-09-11","game":"duo","number":4,"difficulty":"easy",
         "spec":{"n":6,"givens":[[null,0,null,null,null,null],[null,null,null,null,null,null],
                  [null,null,null,null,null,null],[null,null,null,null,null,null],
                  [null,null,null,null,null,null],[null,null,null,null,null,null]],
                 "eq":[[0,0,0,1]],"ne":[[1,0,1,1]]}}
        """)
        guard case .duo(let spec) = started.spec else {
            return XCTFail("expected .duo, got \(started.spec)")
        }
        XCTAssertEqual(spec.n, 6)
        XCTAssertEqual(spec.givens[0][1], 0)
        XCTAssertEqual(spec.eq, [[0, 0, 0, 1]])
        XCTAssertEqual(spec.ne, [[1, 0, 1, 1]])
        XCTAssertEqual(started.spec.kind, .duo)
    }

    func testStartedGameDecodesTrailSpec() throws {
        let started = try decode(StartedGame.self, """
        {"date":"2026-09-11","game":"trail","number":7,"difficulty":"hard",
         "spec":{"n":5,"waypoints":[[0,0],[4,4]]}}
        """)
        XCTAssertEqual(started.spec, .trail(TrailSpec(n: 5, waypoints: [[0, 0], [4, 4]])))
        XCTAssertEqual(started.spec.kind, .trail)
    }

    func testStartedGameDecodesQuintSpec() throws {
        let started = try decode(StartedGame.self, """
        {"date":"2026-09-11","game":"quint","number":12,"difficulty":"medium",
         "spec":{"n":5,"guesses":6,"answer":"crane"}}
        """)
        XCTAssertEqual(started.spec, .quint(QuintSpec(n: 5, guesses: 6, answer: "crane")))
        XCTAssertEqual(started.spec.kind, .quint)
    }

    func testStartedGameRejectsAMismatchedSpec() {
        // `game` says "stars" but `spec` has Trail's shape.
        XCTAssertThrowsError(try decode(StartedGame.self, """
        {"date":"2026-09-11","game":"stars","number":12,"difficulty":"medium",
         "spec":{"n":5,"waypoints":[[0,0],[4,4]]}}
        """)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("expected DecodingError.dataCorrupted, got \(error)")
            }
        }
    }

    // MARK: GameAnswer — exact wire encoding

    func testGameAnswerEncodesStars() throws {
        let data = try JSONEncoder().encode(GameAnswer.stars([0, 2, 1]))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"stars":[0,2,1]}"#)
    }

    func testGameAnswerEncodesDuo() throws {
        let data = try JSONEncoder().encode(GameAnswer.duo([[0, 1], [1, 0]]))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"cells":[[0,1],[1,0]]}"#)
    }

    func testGameAnswerEncodesTrail() throws {
        let data = try JSONEncoder().encode(GameAnswer.trail([[0, 0], [0, 1]]))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"path":[[0,0],[0,1]]}"#)
    }

    func testGameAnswerEncodesQuint() throws {
        let data = try JSONEncoder().encode(GameAnswer.quint(["slate", "crane"]))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"guesses":["slate","crane"]}"#)
    }
}
