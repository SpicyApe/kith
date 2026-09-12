import XCTest

/// Base class for the live end-to-end suite (`apps/ios/TESTING.md` §7).
///
/// This target is deliberately separate from `KithUITests`: the hermetic suite launches
/// with `-uiTesting`, which swaps the whole backend for `FakeKithAPI`, while this one
/// launches WITHOUT it so the app uses the real `Config.plist` and talks to the live
/// Supabase project. The only launch argument here is `-uiTestingControls`, which renders
/// the per-tile ▲ / ▼ buttons (TESTING.md §1, §3) without touching the wiring.
///
/// The helpers below are a copy of `KithUITests/UITestSupport.swift` rather than a shared
/// file: two XCUITest bundles cannot share sources without introducing a package, and the
/// duplication keeps the hermetic suite's behaviour frozen if this one has to drift.
/// Nothing here imports the app target — UI tests run out of process.
@MainActor class KithLiveTestCase: XCTestCase {

    /// TESTING.md §7: "every wait 20 s". Live requests go over the network from a CI
    /// simulator, so this is the floor for anything that involves the backend.
    static let timeout: TimeInterval = 20
    /// Cold start plus the live bootstrap round-trip (session restore, profile, puzzle)
    /// before the first element can possibly exist. Only used for the first lookup after
    /// launch and for the tab bar itself.
    static let launchTimeout: TimeInterval = 40
    /// Used for the optional branches (the onboarding tail, the name step): absence is a
    /// legitimate outcome, so these must not burn a full 20 s each.
    static let optionalTimeout: TimeInterval = 5

    /// The app under test for the current test method.
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Inputs (TESTING.md §7)

    /// The E.164 number registered under Supabase Auth → Phone → Test Phone Numbers.
    /// xcodebuild passes it through as `TEST_RUNNER_KITH_TEST_PHONE`; XCTest strips the
    /// prefix before the runner process sees it, so read the bare name and accept the
    /// prefixed one as a fallback.
    var testPhone: String? { Self.environmentValue("KITH_TEST_PHONE") }

    /// The fixed OTP paired with `testPhone` in that same Supabase table.
    var testOTP: String? { Self.environmentValue("KITH_TEST_OTP") }

    private static func environmentValue(_ name: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        let raw = environment[name] ?? environment["TEST_RUNNER_\(name)"]
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Launching

    /// Launches the app against the REAL backend with the test-only reorder controls on.
    /// Note what is *not* here: `-uiTesting`. That argument, and only that argument,
    /// selects `FakeKithAPI` (TESTING.md §1).
    @discardableResult
    func launchLive() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingControls"]
        app.launch()
        self.app = app
        return app
    }

    // MARK: - Diagnostics

    /// Attaches a screenshot of the current screen named after the step, so a CI failure
    /// is diagnosable from the `.xcresult` alone (TESTING.md §7). Also logs the step, which
    /// puts a timestamped marker next to the attachment in the test log.
    func step(_ name: String) {
        NSLog("[KithLiveTests] step: %@", name)
        guard let app else { return }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Element lookup

    /// Any element with this accessibility identifier, regardless of element type. Used
    /// for things whose SwiftUI-to-XCUIElement type is not worth pinning down (cards,
    /// headers, rows, headlines).
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A tab-bar item. SwiftUI usually surfaces `TabView` items as `tabBars` buttons, but
    /// an identifier placed on the label rather than the item can land in the plain button
    /// query instead — so try both, then fall back to the visible title.
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

    /// A text field by identifier. A six-box OTP field or a `SecureField` does not land in
    /// the plain `textFields` query, so fall back the same way `tab(_:)` does.
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

    // MARK: - Assertions and interactions

    /// Waits for `element` to exist, failing (and stopping, because `continueAfterFailure`
    /// is false) if it never appears. Returns the element so calls can be chained.
    @discardableResult
    func awaitElement(_ element: XCUIElement,
                      _ message: String,
                      timeout: TimeInterval = KithLiveTestCase.timeout,
                      file: StaticString = #filePath,
                      line: UInt = #line) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            // Include the on-screen accessibility tree so a CI failure is diagnosable from
            // the printed summary alone (screenshots need Apple tooling to open).
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "failure: " + message
            shot.lifetime = .keepAlways
            add(shot)
            let tree = String(app.debugDescription.prefix(3000))
            XCTFail(message + "
--- screen at failure ---
" + tree, file: file, line: line)
        }
        return element
    }

    /// Waits for an element and taps it.
    @discardableResult
    func awaitAndTap(_ element: XCUIElement,
                     _ message: String,
                     timeout: TimeInterval = KithLiveTestCase.timeout,
                     file: StaticString = #filePath,
                     line: UInt = #line) -> XCUIElement {
        awaitElement(element, message, timeout: timeout, file: file, line: line).tap()
        return element
    }

    /// Waits for a tab item and taps it, confirming it actually became selected: a tap that
    /// lands mid-animation can be dropped on a busy simulator, so re-tap once if it did not.
    @discardableResult
    func tapTab(_ identifier: String,
                _ message: String,
                file: StaticString = #filePath,
                line: UInt = #line) -> XCUIElement {
        let item = tab(identifier)
        awaitAndTap(item, message, file: file, line: line)
        let selected = NSPredicate(format: "isSelected == true")
        let became = XCTNSPredicateExpectation(predicate: selected, object: item)
        if XCTWaiter().wait(for: [became], timeout: 3) != .completed {
            item.tap()
            let again = XCTNSPredicateExpectation(predicate: selected, object: item)
            _ = XCTWaiter().wait(for: [again], timeout: 5)
        }
        return item
    }

    /// Taps a text field to focus it and types into it. The keyboard is dismissed later by
    /// tapping the step's continue button, never by pressing Return.
    func typeInto(_ field: XCUIElement,
                  _ text: String,
                  _ message: String,
                  file: StaticString = #filePath,
                  line: UInt = #line) {
        awaitAndTap(field, message, file: file, line: line)
        field.typeText(text)
        // Verify the text landed (a tap that arrives mid-transition can leave the field
        // unfocused); retry once before giving up.
        let landed = { (String(describing: field.value ?? "")).contains(text) }
        if !landed() {
            field.tap()
            field.typeText(text)
        }
        XCTAssertTrue(landed(), message + " (typed text did not land)", file: file, line: line)
    }

    /// Waits for an element to become enabled, then asserts it is. Polling the predicate is
    /// more reliable than reading `isEnabled` immediately (the button flips state on the
    /// next SwiftUI render) and, unlike a sleep, returns as soon as the state changes.
    func awaitEnabled(_ element: XCUIElement,
                      _ message: String,
                      timeout: TimeInterval = KithLiveTestCase.timeout,
                      file: StaticString = #filePath,
                      line: UInt = #line) {
        awaitElement(element, message, timeout: timeout, file: file, line: line)
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: element,
                                  handler: nil)
        wait(for: [enabled], timeout: timeout)
        XCTAssertTrue(element.isEnabled, message, file: file, line: line)
    }

    /// True when `element` shows up within `timeout`. For branches where absence is a
    /// legitimate outcome, so it asserts nothing.
    func appears(_ element: XCUIElement, within timeout: TimeInterval = KithLiveTestCase.optionalTimeout) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Taps `element` if it shows up within `timeout`, and reports whether it did. Used for
    /// the onboarding tail, which only a brand-new account sees (TESTING.md §7 step 3).
    @discardableResult
    func tapIfPresent(_ element: XCUIElement,
                      within timeout: TimeInterval = KithLiveTestCase.optionalTimeout) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    /// Asserts that an element's accessibility label contains `substring`.
    func assertLabelContains(_ element: XCUIElement,
                             _ substring: String,
                             _ message: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        awaitElement(element, message, file: file, line: line)
        let label = element.label
        XCTAssertTrue(label.contains(substring),
                      "\(message) — label was \"\(label)\"",
                      file: file, line: line)
    }
}
