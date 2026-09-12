import XCTest

/// Base class for every Kith UI test.
///
/// See `apps/ios/TESTING.md` §1 (launch arguments), §3 (accessibility identifiers)
/// and §5 (the test list). Nothing here reaches into the app target: UI tests run
/// out of process, so this file deliberately imports `XCTest` only.
@MainActor class KithUITestCase: XCTestCase {

    /// Every existence wait in the suite uses this. Simulator cold starts on CI are
    /// slower than a developer Mac, so it is deliberately generous. We never sleep.
    static let timeout: TimeInterval = 8
    /// First lookup after launch: the simulator can take a while to reach the tabs on CI.
    static let launchTimeout: TimeInterval = 25

    /// The app under test for the current test method. One launch per test keeps the
    /// tests independent: the fake backend and its `FileStore` are rebuilt each time.
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Launching

    /// Launches the app wired to the in-memory fakes in the given starting state.
    /// `state` is one of `fresh`, `returning`, `played` (TESTING.md §2).
    @discardableResult
    func launch(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingState", state]
        app.launch()
        self.app = app
        return app
    }

    // MARK: - Element lookup

    /// Any element with this accessibility identifier, regardless of element type.
    /// Used for things whose SwiftUI-to-XCUIElement type is not worth pinning down
    /// (board rows, headers, cards, chips).
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A tab-bar item. SwiftUI usually surfaces `TabView` items as `tabBars` buttons,
    /// but an identifier placed on the label rather than the item can land in the plain
    /// button query instead — so try both (per the task contract).
    /// Tab bar buttons are matched by identifier first and by their visible title as a
    /// fallback: SwiftUI does not always surface a `tabItem` label's identifier on the
    /// UITabBar button, and which one XCUITest sees has proven flaky on CI simulators.
    func tab(_ identifier: String) -> XCUIElement {
        let titles = ["tab.today": "Today", "tab.board": "Board", "tab.circles": "Circles", "tab.you": "You"]
        let bar = app.tabBars.firstMatch
        _ = bar.waitForExistence(timeout: Self.launchTimeout)
        let byIdentifier = bar.buttons[identifier]
        if byIdentifier.waitForExistence(timeout: 3) {
            return byIdentifier
        }
        if let title = titles[identifier] {
            let byTitle = bar.buttons[title]
            if byTitle.waitForExistence(timeout: 3) {
                return byTitle
            }
        }
        return app.buttons[identifier]
    }

    // MARK: - Assertions and interactions

    /// Waits for `element` to exist, failing the test (and stopping it, because
    /// `continueAfterFailure` is false) if it never appears. Returns the element so
    /// calls can be chained into a tap.
    @discardableResult
    func awaitElement(_ element: XCUIElement,
                      _ message: String? = nil,
                      timeout: TimeInterval = KithUITestCase.timeout,
                      file: StaticString = #filePath,
                      line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      message ?? "Timed out waiting for \(element)",
                      file: file, line: line)
        return element
    }

    /// Waits for an element and taps it.
    @discardableResult
    func awaitAndTap(_ element: XCUIElement,
                     _ message: String? = nil,
                     timeout: TimeInterval = KithUITestCase.timeout,
                     file: StaticString = #filePath,
                     line: UInt = #line) -> XCUIElement {
        awaitElement(element, message, timeout: timeout, file: file, line: line).tap()
        return element
    }

    /// Waits for a tab item and taps it.
    @discardableResult
    func tapTab(_ identifier: String,
                file: StaticString = #filePath,
                line: UInt = #line) -> XCUIElement {
        let item = tab(identifier)
        awaitAndTap(item, "Tab \(identifier) never appeared", file: file, line: line)
        // A tap that lands mid-animation can be dropped on a busy simulator; confirm the
        // tab actually became selected and tap once more if it did not.
        let selected = NSPredicate(format: "isSelected == true")
        let became = XCTNSPredicateExpectation(predicate: selected, object: item)
        if XCTWaiter().wait(for: [became], timeout: 3) != .completed {
            item.tap()
            let again = XCTNSPredicateExpectation(predicate: selected, object: item)
            _ = XCTWaiter().wait(for: [again], timeout: 5)
        }
        return item
    }

    /// Taps a text field to focus it and types into it. The keyboard is dismissed later
    /// by tapping the step's continue button, never by pressing Return: the fields in
    /// onboarding do not all have a submit action wired to the return key.
    func typeInto(_ field: XCUIElement,
                  _ text: String,
                  file: StaticString = #filePath,
                  line: UInt = #line) {
        awaitAndTap(field, "Text field never appeared", file: file, line: line)
        field.typeText(text)
    }

    /// Waits for an element to become enabled, then asserts it is. Used after a move
    /// re-enables `today.lockIn`: the button flips state on the next SwiftUI render,
    /// so polling the predicate is more reliable than reading `isEnabled` immediately
    /// (and unlike a sleep it returns as soon as the state actually changes).
    func awaitEnabled(_ element: XCUIElement,
                      _ message: String? = nil,
                      timeout: TimeInterval = KithUITestCase.timeout,
                      file: StaticString = #filePath,
                      line: UInt = #line) {
        awaitElement(element, message, timeout: timeout, file: file, line: line)
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: element,
                                  handler: nil)
        wait(for: [enabled], timeout: timeout)
        XCTAssertTrue(element.isEnabled,
                      message ?? "Expected \(element) to be enabled",
                      file: file, line: line)
    }

    /// Waits for an element to become disabled, then asserts it is. Same reasoning as
    /// `awaitEnabled`, for the other direction (`board.period` after picking Everyone).
    func awaitDisabled(_ element: XCUIElement,
                       _ message: String? = nil,
                       timeout: TimeInterval = KithUITestCase.timeout,
                       file: StaticString = #filePath,
                       line: UInt = #line) {
        awaitElement(element, message, timeout: timeout, file: file, line: line)
        let disabled = expectation(for: NSPredicate(format: "isEnabled == false"),
                                   evaluatedWith: element,
                                   handler: nil)
        wait(for: [disabled], timeout: timeout)
        XCTAssertFalse(element.isEnabled,
                       message ?? "Expected \(element) to be disabled",
                       file: file, line: line)
    }

    /// A text field by identifier. A six-box OTP field or a `SecureField` does not land
    /// in the plain `textFields` query, so fall back the same way `tab(_:)` does.
    func textField(_ identifier: String) -> XCUIElement {
        let plain = app.textFields[identifier]
        if plain.waitForExistence(timeout: Self.timeout) {
            return plain
        }
        let secure = app.secureTextFields[identifier]
        if secure.exists {
            return secure
        }
        return element(identifier)
    }

    /// Asserts that an element's accessibility label contains `substring`.
    func assertLabelContains(_ element: XCUIElement,
                             _ substring: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        awaitElement(element, file: file, line: line)
        let label = element.label
        XCTAssertTrue(label.contains(substring),
                      "Expected label to contain \"\(substring)\" but it was \"\(label)\"",
                      file: file, line: line)
    }

    /// Asserts that an element's accessibility label equals `expected` exactly.
    func assertLabelEquals(_ element: XCUIElement,
                           _ expected: String,
                           file: StaticString = #filePath,
                           line: UInt = #line) {
        awaitElement(element, file: file, line: line)
        XCTAssertEqual(element.label, expected, file: file, line: line)
    }
}
