// ContactsSyncTests.swift — TESTING.md §4 test 12.

import Foundation
import KithCore
import XCTest
@testable import Kith

@MainActor
final class ContactsSyncTests: XCTestCase {

    /// §4.12. Under iOS 18 "limited" access the fetch only ever sees the contacts the
    /// user picked, so a hash missing from it has not necessarily left the address book.
    /// The sync must send no removals and must not claim a full sync.
    ///
    /// The simulator has no contacts permission, so the test drives the half of
    /// `ContactsService.sync` that takes the address book and the authorization state as
    /// parameters; the production path is the other overload calling straight into this.
    func testLimitedContactsSyncNeverRemoves() async throws {
        let api = FakeKithAPI(state: .returning)

        let contacts = [
            RawContact(name: "Mum", numbers: ["+15550000001"]),
            RawContact(name: "Sam", numbers: ["+15550000002"]),
            RawContact(name: "Dev", numbers: ["+15550000003"]),
        ]
        // A hash that is no longer visible: a full-access sync would send it as a removal.
        let goneHash = SHA256.hex("+15559999999")
        let lastSynced: Set<String> = [goneHash]

        let outcome = try await ContactsService.sync(
            api: api,
            lastSynced: lastSynced,
            contacts: contacts,
            isLimited: true
        )

        let call = try XCTUnwrap(
            api.calls.first { $0.hasPrefix("matchContacts(") },
            "no matchContacts call in \(api.calls)"
        )
        XCTAssertEqual(call, "matchContacts(added:3,removed:0,full:false)")

        // The hash we can no longer see stays on the server, and stays in our record of
        // what the server holds.
        XCTAssertTrue(outcome.syncedHashes.contains(goneHash))
        XCTAssertEqual(outcome.syncedHashes.count, 4)
        XCTAssertEqual(outcome.matches.count, 3)
        XCTAssertEqual(outcome.friends.count, 3)
        XCTAssertEqual(outcome.sharedCount, 3)
        XCTAssertEqual(outcome.directory.name(forHash: SHA256.hex("+15550000001")), "Mum")
    }

    /// The same input with full access does send the removal, so the assertion above is
    /// about the limited branch and not about the planner being a no-op.
    func testFullAccessSyncSendsRemovals() async throws {
        let api = FakeKithAPI(state: .returning)
        let contacts = [RawContact(name: "Mum", numbers: ["+15550000001"])]
        let lastSynced: Set<String> = [SHA256.hex("+15559999999")]

        _ = try await ContactsService.sync(
            api: api,
            lastSynced: lastSynced,
            contacts: contacts,
            isLimited: false
        )

        let call = try XCTUnwrap(api.calls.first { $0.hasPrefix("matchContacts(") })
        XCTAssertEqual(call, "matchContacts(added:1,removed:1,full:false)")
    }
}
