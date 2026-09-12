// TestHarness.swift — one `AppModel` wired to the fakes, with its own throwaway cache.
// See apps/ios/TESTING.md §4.

import Foundation
import XCTest
@testable import Kith

/// `AppModel(auth: FakeAuth(), api: FakeKithAPI(state:), store: FileStore(directory: temp))`,
/// which is the only construction the unit tests use.
@MainActor
struct Harness {
    let model: AppModel
    let api: FakeKithAPI
    let auth: FakeAuth
    /// The temporary directory `model`'s `FileStore` writes into.
    let directory: URL

    init(_ state: FakeKithAPI.State) {
        let api = FakeKithAPI(state: state)
        // `fresh` is the signed-out start; the other two states resume a session.
        let auth = FakeAuth(signedIn: state != .fresh)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KithTests-\(UUID().uuidString)", isDirectory: true)

        self.api = api
        self.auth = auth
        self.directory = directory
        self.model = AppModel(auth: auth, api: api, store: FileStore(directory: directory))
    }

    /// Boots the model the way `KithApp` does.
    func boot() async {
        await model.bootstrap()
    }

    func callCount(_ name: String) -> Int {
        api.calls.filter { $0 == name || $0.hasPrefix("\(name)(") }.count
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
