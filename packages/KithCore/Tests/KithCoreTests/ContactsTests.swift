import XCTest
@testable import KithCore

/// A `PhoneNormalizing` test double whose numbers are already "normalized": any raw
/// string is passed through unchanged as the E.164 value, except the literal "bad"
/// which is treated as unparseable. This isolates `ContactDirectory.build` tests from
/// `BasicPhoneNormalizer`'s own (separately tested) behavior.
private struct PassthroughNormalizer: PhoneNormalizing {
    func e164(_ raw: String, defaultRegion: String) -> String? {
        raw == "bad" ? nil : raw
    }
}

final class ContactsTests: XCTestCase {
    private let normalizer = PassthroughNormalizer()

    // MARK: ContactDirectory.build

    func testBuildFirstNameWinsWhenTwoContactsShareANumber() {
        let contacts = [
            RawContact(name: "Alice", numbers: ["+15551111111"]),
            RawContact(name: "Bob", numbers: ["+15551111111"]),
        ]
        let directory = ContactDirectory.build(from: contacts, normalizer: normalizer, region: "US")

        XCTAssertEqual(directory.name(forHash: SHA256.hex("+15551111111")), "Alice")
        XCTAssertEqual(directory.hashes.count, 1)
    }

    func testBuildSkipsUnparseableNumbers() {
        let contacts = [
            RawContact(name: "Charlie", numbers: ["bad", "+15553333333"]),
        ]
        let directory = ContactDirectory.build(from: contacts, normalizer: normalizer, region: "US")

        XCTAssertEqual(directory.hashes.count, 1)
        XCTAssertEqual(directory.name(forHash: SHA256.hex("+15553333333")), "Charlie")
    }

    func testBuildHashesAreSHA256OfE164() {
        let contacts = [
            RawContact(name: "Dev from work", numbers: ["+15559998888"]),
        ]
        let directory = ContactDirectory.build(from: contacts, normalizer: normalizer, region: "US")

        XCTAssertEqual(directory.hashes, [SHA256.hex("+15559998888")])
    }

    func testBuildHashesSetSizeCountsUniqueNumbersOnly() {
        let contacts = [
            RawContact(name: "Erin", numbers: ["+15551000000", "+15552000000"]),
            RawContact(name: "Frank", numbers: ["+15552000000", "bad"]), // shares one with Erin, one unparseable
            RawContact(name: "Grace", numbers: ["+15553000000"]),
        ]
        let directory = ContactDirectory.build(from: contacts, normalizer: normalizer, region: "US")

        // Three distinct parseable numbers were seen: 1000000, 2000000, 3000000.
        XCTAssertEqual(directory.hashes.count, 3)
        XCTAssertEqual(
            directory.hashes,
            Set(["+15551000000", "+15552000000", "+15553000000"].map(SHA256.hex))
        )
        // Erin's contact was listed first, so her name wins for the shared number.
        XCTAssertEqual(directory.name(forHash: SHA256.hex("+15552000000")), "Erin")
    }

    /// iOS 18 "limited access" hands over a subset of the address book. The directory is
    /// built from exactly what was shared — nothing infers the contacts that were withheld.
    func testBuildOverATwoOfTenSubsetOnlyKnowsTheSharedPair() {
        let everyone = (0..<10).map { RawContact(name: "Person \($0)", numbers: ["+1555000000\($0)"]) }
        let shared = [everyone[3], everyone[7]] // what a limited-access fetch returns

        let directory = ContactDirectory.build(from: shared, normalizer: normalizer, region: "US")

        XCTAssertEqual(directory.hashes.count, 2)
        XCTAssertEqual(
            directory.hashes,
            Set(["+15550000003", "+15550000007"].map(SHA256.hex))
        )
        XCTAssertEqual(directory.name(forHash: SHA256.hex("+15550000003")), "Person 3")
        XCTAssertEqual(directory.name(forHash: SHA256.hex("+15550000007")), "Person 7")
        // The eight contacts that were not shared are absent, not merely unnamed.
        for index in [0, 1, 2, 4, 5, 6, 8, 9] {
            XCTAssertNil(
                directory.name(forHash: SHA256.hex("+1555000000\(index)")),
                "contact \(index) was never shared and must not be in the directory"
            )
        }
    }

    // MARK: ContactSyncPlanner.plan

    func testPlanNeverSyncedIsFullWithSortedHashes() {
        let current: Set<String> = ["c", "a", "b"]
        let plan = ContactSyncPlanner.plan(current: current, lastSynced: nil)

        XCTAssertTrue(plan.full)
        XCTAssertEqual(plan.added, ["a", "b", "c"])
        XCTAssertEqual(plan.removed, [])
    }

    func testPlanDiffAddedAndRemovedAreSorted() {
        let current: Set<String> = ["b", "a", "d"]
        let last: Set<String> = ["e", "c", "a"]
        let plan = ContactSyncPlanner.plan(current: current, lastSynced: last)

        XCTAssertFalse(plan.full)
        XCTAssertEqual(plan.added, ["b", "d"])   // current - last, sorted
        XCTAssertEqual(plan.removed, ["c", "e"]) // last - current, sorted
    }

    func testPlanUnchangedIsEmpty() {
        let hashes: Set<String> = ["a", "b", "c"]
        let plan = ContactSyncPlanner.plan(current: hashes, lastSynced: hashes)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertFalse(plan.full)
        XCTAssertEqual(plan.added, [])
        XCTAssertEqual(plan.removed, [])
    }

    /// Deleting contacts (and adding none) must produce a removal-only diff, never a full
    /// re-sync — the server rate-limits those to one an hour.
    func testPlanShrinkingSetProducesRemovedOnly() {
        let last: Set<String> = ["a", "b", "c", "d"]
        let current: Set<String> = ["a", "c"]

        let plan = ContactSyncPlanner.plan(current: current, lastSynced: last)

        XCTAssertFalse(plan.full)
        XCTAssertEqual(plan.added, [])
        XCTAssertEqual(plan.removed, ["b", "d"])
        XCTAssertFalse(plan.isEmpty)
    }

    func testPlanBigDiffFallsBackToFullWhenCurrentFitsWithinMax() {
        let current = Set((0..<5).map { "cur\($0)" })
        let last = Set((0..<5).map { "old\($0)" })
        // added.count (5) + removed.count (5) = 10 > maxPerRequest (5), but
        // current.count (5) <= maxPerRequest (5) -> full sync fallback.
        let plan = ContactSyncPlanner.plan(current: current, lastSynced: last, maxPerRequest: 5)

        XCTAssertTrue(plan.full)
        XCTAssertEqual(plan.added, current.sorted())
        XCTAssertEqual(plan.removed, [])
    }

    func testPlanBigDiffTruncatesAddedWhenCurrentExceedsMax() {
        let current = Set((1...6).map { "a\($0)" })  // 6 hashes, all new
        let last: Set<String> = ["o1", "o2"]          // 2 hashes, both gone
        let maxPerRequest = 5
        // added.count (6) + removed.count (2) = 8 > max (5); current.count (6) > max (5)
        // -> truncate added to the first (max - removed.count) sorted hashes.
        let plan = ContactSyncPlanner.plan(current: current, lastSynced: last, maxPerRequest: maxPerRequest)

        XCTAssertFalse(plan.full)
        XCTAssertEqual(plan.removed, ["o1", "o2"])
        XCTAssertEqual(plan.added.count, maxPerRequest - plan.removed.count)
        XCTAssertEqual(plan.added, ["a1", "a2", "a3"])
    }

    // MARK: FriendNames.displayName

    func testDisplayNameUsesAddressBookNameWhenHashIsKnown() {
        let friend = Friend(userId: "u1", displayName: "Bob (server)")
        let matched = MatchedContact(userId: "u1", displayName: "Bob (server)", hash: "hash1")
        let directory = ContactDirectory(namesByHash: ["hash1": "Bobby (mine)"])

        XCTAssertEqual(
            FriendNames.displayName(for: friend, matches: [matched], directory: directory),
            "Bobby (mine)"
        )
    }

    func testDisplayNameFallsBackToServerNameWhenHashIsUnknown() {
        let friend = Friend(userId: "u2", displayName: "Carol (server)")
        let matched = MatchedContact(userId: "u2", displayName: "Carol (server)", hash: "hash2")
        let directory = ContactDirectory(namesByHash: [:]) // "hash2" not present

        XCTAssertEqual(
            FriendNames.displayName(for: friend, matches: [matched], directory: directory),
            "Carol (server)"
        )
    }

    func testDisplayNameFallsBackToServerNameWhenNoMatchEchoedTheirHash() {
        let friend = Friend(userId: "u3", displayName: "Dave (server)")

        XCTAssertEqual(
            FriendNames.displayName(for: friend, matches: [], directory: ContactDirectory()),
            "Dave (server)"
        )
    }
}
