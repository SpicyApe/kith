// QuintTests.swift — QuintEngine, GameScoring.quintScore, and the Quint share text header.

import XCTest
@testable import GridGames

final class QuintTests: XCTestCase {

    private func spec(answer: String = "crane") -> QuintSpec {
        QuintSpec(n: 5, guesses: 6, answer: answer)
    }

    // MARK: - init validation

    func testInitRejectsWrongN() {
        XCTAssertThrowsError(try QuintEngine(spec: QuintSpec(n: 4, guesses: 6, answer: "crane")))
    }

    func testInitRejectsShortAnswer() {
        XCTAssertThrowsError(try QuintEngine(spec: QuintSpec(n: 5, guesses: 6, answer: "cran")))
    }

    func testInitRejectsUppercaseAnswer() {
        XCTAssertThrowsError(try QuintEngine(spec: QuintSpec(n: 5, guesses: 6, answer: "CRANE")))
    }

    func testInitRejectsNonLetterAnswer() {
        XCTAssertThrowsError(try QuintEngine(spec: QuintSpec(n: 5, guesses: 6, answer: "cra1e")))
    }

    func testInitAccepts() throws {
        let engine = try QuintEngine(spec: spec())
        XCTAssertEqual(engine.guesses, [])
        XCTAssertEqual(engine.current, "")
    }

    // MARK: - marks() duplicate-letter rule

    func testMarksEerieVsThere() {
        XCTAssertEqual(QuintEngine.marks(guess: "eerie", answer: "there"),
                        [.near, .miss, .near, .miss, .hit])
    }

    func testMarksAlleeVsEagle() {
        XCTAssertEqual(QuintEngine.marks(guess: "allee", answer: "eagle"),
                        [.near, .near, .miss, .near, .hit])
    }

    func testMarksGeeseVsEases() {
        XCTAssertEqual(QuintEngine.marks(guess: "geese", answer: "eases"),
                        [.miss, .near, .near, .near, .miss])
    }

    func testMarksExactMatch() {
        XCTAssertEqual(QuintEngine.marks(guess: "crane", answer: "crane"),
                        [.hit, .hit, .hit, .hit, .hit])
    }

    func testMarksNoOverlap() {
        XCTAssertEqual(QuintEngine.marks(guess: "chunk", answer: "trade"),
                        [.miss, .miss, .miss, .miss, .miss])
    }

    // MARK: - typing / backspace

    func testTypeAppendsLowercased() throws {
        var engine = try QuintEngine(spec: spec())
        XCTAssertTrue(engine.type("C"))
        XCTAssertEqual(engine.current, "c")
    }

    func testTypeIgnoresNonLetters() throws {
        var engine = try QuintEngine(spec: spec())
        XCTAssertFalse(engine.type("1"))
        XCTAssertFalse(engine.type(" "))
        XCTAssertFalse(engine.type("-"))
        XCTAssertEqual(engine.current, "")
    }

    func testTypeIgnoresWhenFull() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "crane" { XCTAssertTrue(engine.type(letter)) }
        XCTAssertEqual(engine.current, "crane")
        XCTAssertFalse(engine.type("x"))
        XCTAssertEqual(engine.current, "crane")
    }

    func testTypeIgnoresWhenFinished() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "crane" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .accepted)
        XCTAssertTrue(engine.isComplete)
        XCTAssertFalse(engine.type("x"))
        XCTAssertEqual(engine.current, "")
    }

    func testBackspaceRemovesLastLetter() throws {
        var engine = try QuintEngine(spec: spec())
        engine.type("c")
        engine.type("r")
        engine.backspace()
        XCTAssertEqual(engine.current, "c")
    }

    func testBackspaceOnEmptyIsNoOp() throws {
        var engine = try QuintEngine(spec: spec())
        engine.backspace()
        XCTAssertEqual(engine.current, "")
    }

    // MARK: - submit()

    func testSubmitTooShort() throws {
        var engine = try QuintEngine(spec: spec())
        engine.type("c")
        engine.type("r")
        XCTAssertEqual(engine.submit(), .tooShort)
        XCTAssertEqual(engine.current, "cr")
        XCTAssertEqual(engine.guesses, [])
    }

    func testSubmitNotAWord() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "zzzzz" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .notAWord)
        XCTAssertEqual(engine.current, "zzzzz")
        XCTAssertEqual(engine.guesses, [])
    }

    func testSubmitAccepted() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "slate" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .accepted)
        XCTAssertEqual(engine.guesses, ["slate"])
        XCTAssertEqual(engine.current, "")
    }

    func testSubmitFinishedAfterComplete() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "crane" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .accepted)
        XCTAssertEqual(engine.submit(), .finished)
    }

    // MARK: - solved / failed / complete

    func testSolvedInThree() throws {
        var engine = try QuintEngine(spec: spec())
        for word in ["slate", "crimp", "crane"] {
            for letter in word { engine.type(letter) }
            XCTAssertEqual(engine.submit(), .accepted)
        }
        XCTAssertTrue(engine.isSolved)
        XCTAssertFalse(engine.isFailed)
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.wrongGuesses, 2)
        XCTAssertEqual(engine.guessesAnswer, ["slate", "crimp", "crane"])
    }

    func testFailedAfterSix() throws {
        var engine = try QuintEngine(spec: spec())
        let wrongWords = ["slate", "crimp", "brown", "flute", "words", "chess"]
        for word in wrongWords {
            for letter in word { engine.type(letter) }
            XCTAssertEqual(engine.submit(), .accepted)
        }
        XCTAssertFalse(engine.isSolved)
        XCTAssertTrue(engine.isFailed)
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.wrongGuesses, 6)
    }

    // MARK: - keyMarks

    func testKeyMarksBestOf() throws {
        var engine = try QuintEngine(spec: spec())
        // "arena" vs "crane": a is near (pos0) then... check both guesses give 'a' different marks;
        // best (highest) mark should win.
        for letter in "arena" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .accepted)
        for letter in "crane" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .accepted)
        // 'a' is near in "arena" (index0) but hit in "crane" (index2) -> best is .hit
        XCTAssertEqual(engine.keyMarks["a"], .hit)
        // 'c' only appears in "crane" as a hit.
        XCTAssertEqual(engine.keyMarks["c"], .hit)
    }

    func testKeyMarksMissStaysMissWhenNeverSeenAgain() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "chunk" { engine.type(letter) }
        XCTAssertEqual(engine.submit(), .accepted)
        XCTAssertEqual(engine.keyMarks["u"], .miss)
    }

    // MARK: - shareRows

    func testShareRows() throws {
        var engine = try QuintEngine(spec: spec())
        for word in ["slate", "crane"] {
            for letter in word { engine.type(letter) }
            XCTAssertEqual(engine.submit(), .accepted)
        }
        XCTAssertEqual(engine.shareRows(), ["⬛️⬛️🟩⬛️🟩", "🟩🟩🟩🟩🟩"])
    }

    // MARK: - reset

    func testReset() throws {
        var engine = try QuintEngine(spec: spec())
        for letter in "slate" { engine.type(letter) }
        engine.submit()
        engine.type("c")
        engine.reset()
        XCTAssertEqual(engine.guesses, [])
        XCTAssertEqual(engine.current, "")
    }

    // MARK: - GameScoring.quintScore

    func testQuintScoreTableAtZeroSeconds() {
        // one guess is 1000 before time, six guesses 500 (docs/07 §Quint Scoring).
        let expected = [1000, 900, 800, 700, 600, 500]
        for (i, guesses) in (1...6).enumerated() {
            XCTAssertEqual(GameScoring.quintScore(elapsedMs: 0, guesses: guesses, solved: true, gaveUp: false),
                            expected[i], "guesses=\(guesses)")
        }
    }

    func testQuintScoreTableAt400Seconds() {
        // min(seconds, 300) caps the time penalty at 300.
        let expected = [700, 600, 500, 400, 300, 200]
        for (i, guesses) in (1...6).enumerated() {
            XCTAssertEqual(GameScoring.quintScore(elapsedMs: 400_000, guesses: guesses, solved: true, gaveUp: false),
                            expected[i], "guesses=\(guesses)")
        }
    }

    func testQuintScoreFailIsAlways100() {
        XCTAssertEqual(GameScoring.quintScore(elapsedMs: 0, guesses: 6, solved: false, gaveUp: false), 100)
        XCTAssertEqual(GameScoring.quintScore(elapsedMs: 400_000, guesses: 6, solved: false, gaveUp: false), 100)
    }

    func testQuintScoreGaveUpIsAlways100() {
        XCTAssertEqual(GameScoring.quintScore(elapsedMs: 0, guesses: 3, solved: true, gaveUp: true), 100)
        XCTAssertEqual(GameScoring.quintScore(elapsedMs: 400_000, guesses: 1, solved: true, gaveUp: true), 100)
    }

    // MARK: - GameShareText header

    func testShareTextHeaderSolved() {
        let text = GameShareText.render(game: .quint, number: 12, elapsedMs: 62_000, gaveUp: false,
                                         rows: ["⬛️🟨⬛️⬛️🟩", "🟩🟩⬛️🟨⬛️", "🟩🟩🟩🟩🟩"],
                                         refCode: "7F3Q", quintProgress: "4/6")
        XCTAssertEqual(text, "Kith Quint #12 · 4/6 · 1:02\n⬛️🟨⬛️⬛️🟩\n🟩🟩⬛️🟨⬛️\n🟩🟩🟩🟩🟩\nkith.app/g/quint/12?r=7F3Q")
    }

    func testShareTextHeaderFail() {
        let text = GameShareText.render(game: .quint, number: 12, elapsedMs: 62_000, gaveUp: false,
                                         rows: [], refCode: "7F3Q", quintProgress: "X/6")
        XCTAssertEqual(text, "Kith Quint #12 · X/6 · 1:02\nkith.app/g/quint/12?r=7F3Q")
    }

    func testShareTextOtherGamesUnaffectedByDefault() {
        // Existing call sites (no quintProgress argument) must keep producing the old header shape.
        let text = GameShareText.render(game: .stars, number: 12, elapsedMs: 83_000, gaveUp: false,
                                         rows: ["⭐️⬛️"], refCode: "7F3Q")
        XCTAssertEqual(text, "Kith Stars #12 · 1:23\n⭐️⬛️\nkith.app/g/stars/12?r=7F3Q")
    }
}
