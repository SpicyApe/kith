// GoldenVectorTests.swift — decodes Fixtures/golden.json (one case per game), drives each
// engine to completion via its answer, and checks it against the recorded shareRows / share
// text. A TypeScript test reads the same JSON file later, so keep it plain wire data.

import XCTest
@testable import GridGames

private struct GoldenCase: Decodable {
    let game: GameKind
    let number: Int
    let elapsedMs: Int
    let gaveUp: Bool
    let refCode: String?
    let shareRows: [String]
    let quintProgress: String?
    let shareText: String

    let starsSpec: StarsSpec?
    let starsAnswer: [Int]?
    let duoSpec: DuoSpec?
    let duoAnswer: [[Int]]?
    let trailSpec: TrailSpec?
    let trailAnswer: [[Int]]?
    let quintSpec: QuintSpec?
    let quintAnswer: [String]?

    private enum CodingKeys: String, CodingKey {
        case game, spec, answer, shareRows, number, elapsedMs, gaveUp, refCode, quintProgress, shareText
    }

    private enum QuintAnswerKeys: String, CodingKey {
        case guesses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = try c.decode(GameKind.self, forKey: .game)
        number = try c.decode(Int.self, forKey: .number)
        elapsedMs = try c.decode(Int.self, forKey: .elapsedMs)
        gaveUp = try c.decode(Bool.self, forKey: .gaveUp)
        refCode = try c.decodeIfPresent(String.self, forKey: .refCode)
        shareRows = try c.decode([String].self, forKey: .shareRows)
        quintProgress = try c.decodeIfPresent(String.self, forKey: .quintProgress)
        shareText = try c.decode(String.self, forKey: .shareText)

        var starsSpec: StarsSpec?, duoSpec: DuoSpec?, trailSpec: TrailSpec?, quintSpec: QuintSpec?
        var starsAnswer: [Int]?, duoAnswer: [[Int]]?, trailAnswer: [[Int]]?, quintAnswer: [String]?
        switch game {
        case .stars:
            starsSpec = try c.decode(StarsSpec.self, forKey: .spec)
            starsAnswer = try c.decode([Int].self, forKey: .answer)
        case .duo:
            duoSpec = try c.decode(DuoSpec.self, forKey: .spec)
            duoAnswer = try c.decode([[Int]].self, forKey: .answer)
        case .trail:
            trailSpec = try c.decode(TrailSpec.self, forKey: .spec)
            trailAnswer = try c.decode([[Int]].self, forKey: .answer)
        case .quint:
            quintSpec = try c.decode(QuintSpec.self, forKey: .spec)
            let answerContainer = try c.nestedContainer(keyedBy: QuintAnswerKeys.self, forKey: .answer)
            quintAnswer = try answerContainer.decode([String].self, forKey: .guesses)
        }
        self.starsSpec = starsSpec
        self.duoSpec = duoSpec
        self.trailSpec = trailSpec
        self.quintSpec = quintSpec
        self.starsAnswer = starsAnswer
        self.duoAnswer = duoAnswer
        self.trailAnswer = trailAnswer
        self.quintAnswer = quintAnswer
    }
}

final class GoldenVectorTests: XCTestCase {

    private func loadCases() throws -> [GoldenCase] {
        guard let url = Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("missing Fixtures/golden.json")
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([GoldenCase].self, from: data)
    }

    func testGoldenVectors() throws {
        let cases = try loadCases()
        XCTAssertEqual(Set(cases.map(\.game.rawValue)), ["duo", "quint", "stars", "trail"],
                        "expect at least one case per game")
        let quintCases = cases.filter { $0.game == .quint }
        XCTAssertGreaterThanOrEqual(quintCases.count, 3, "expect solved, fail and give-up quint cases")

        for c in cases {
            switch c.game {
            case .stars:
                try checkStars(c)
            case .duo:
                try checkDuo(c)
            case .trail:
                try checkTrail(c)
            case .quint:
                try checkQuint(c)
            }
        }
    }

    private func checkStars(_ c: GoldenCase) throws {
        guard let spec = c.starsSpec, let answer = c.starsAnswer else {
            return XCTFail("stars case missing spec/answer")
        }
        var engine = try StarsEngine(spec: spec)
        for (row, col) in answer.enumerated() {
            try engine.set(.star, at: GridPoint(row: row, col: col))
        }
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.answer, answer)
        XCTAssertEqual(engine.shareRows(), c.shareRows)
        let text = GameShareText.render(game: .stars, number: c.number, elapsedMs: c.elapsedMs,
                                         gaveUp: c.gaveUp, rows: engine.shareRows(), refCode: c.refCode)
        XCTAssertEqual(text, c.shareText)
    }

    private func checkDuo(_ c: GoldenCase) throws {
        guard let spec = c.duoSpec, let answer = c.duoAnswer else {
            return XCTFail("duo case missing spec/answer")
        }
        var engine = try DuoEngine(spec: spec)
        for r in 0..<spec.n {
            for col in 0..<spec.n {
                try engine.set(answer[r][col], at: GridPoint(row: r, col: col))
            }
        }
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.answer, answer)
        XCTAssertEqual(engine.shareRows(), c.shareRows)
        let text = GameShareText.render(game: .duo, number: c.number, elapsedMs: c.elapsedMs,
                                         gaveUp: c.gaveUp, rows: engine.shareRows(), refCode: c.refCode)
        XCTAssertEqual(text, c.shareText)
    }

    private func checkTrail(_ c: GoldenCase) throws {
        guard let spec = c.trailSpec, let answer = c.trailAnswer else {
            return XCTFail("trail case missing spec/answer")
        }
        var engine = try TrailEngine(spec: spec)
        for pair in answer.dropFirst() {
            let point = GridPoint(row: pair[0], col: pair[1])
            XCTAssertTrue(engine.extend(to: point), "failed to extend to \(point)")
        }
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.answer, answer)
        XCTAssertEqual(engine.shareRows(), c.shareRows)
        let text = GameShareText.render(game: .trail, number: c.number, elapsedMs: c.elapsedMs,
                                         gaveUp: c.gaveUp, rows: engine.shareRows(), refCode: c.refCode)
        XCTAssertEqual(text, c.shareText)
    }

    private func checkQuint(_ c: GoldenCase) throws {
        guard let spec = c.quintSpec, let answer = c.quintAnswer, let quintProgress = c.quintProgress else {
            return XCTFail("quint case missing spec/answer/quintProgress")
        }
        var engine = try QuintEngine(spec: spec)
        for guess in answer {
            for letter in guess {
                XCTAssertTrue(engine.type(letter))
            }
            XCTAssertEqual(engine.submit(), .accepted)
        }
        if !c.gaveUp {
            XCTAssertTrue(engine.isComplete)
        }
        XCTAssertEqual(engine.guessesAnswer, answer)
        XCTAssertEqual(engine.shareRows(), c.shareRows)
        let text = GameShareText.render(game: .quint, number: c.number, elapsedMs: c.elapsedMs,
                                         gaveUp: c.gaveUp, rows: engine.shareRows(), refCode: c.refCode,
                                         quintProgress: quintProgress)
        XCTAssertEqual(text, c.shareText)
    }
}
