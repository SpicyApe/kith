// ContactsService.swift — the Contacts framework, and nothing else.
//
// Normalisation, hashing, diffing and the hash → name map all live in KithCore
// (`BasicPhoneNormalizer`, `ContactDirectory`, `ContactSyncPlanner`). This file only
// reads `CNContactStore` and drives `api.matchContacts`.

import Contacts
import Foundation
import KithCore

/// Authorization, flattened so the rest of the app never imports Contacts.
enum ContactsAuthState: String, Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
    /// iOS 18 "limited access": only the contacts the user picked are visible.
    case limited

    var allowsFetch: Bool { self == .authorized || self == .limited }

    /// docs/03 §5 settings line.
    func statusLine(sharedCount: Int, lastSync: Date?) -> String {
        switch self {
        case .authorized:
            if let lastSync {
                return "Full access · synced \(ContactsService.relativeTime(since: lastSync))"
            }
            return "Full access · not synced yet"
        case .limited:
            return "Limited · \(sharedCount) shared"
        case .denied, .restricted:
            return "Off"
        case .notDetermined:
            return "Not set up"
        }
    }
}

struct ContactSyncOutcome: Sendable, Equatable {
    let directory: ContactDirectory
    let matches: [MatchedContact]
    let friends: [Friend]
    let syncedHashes: Set<String>
    /// Number of address-book entries that produced at least one usable number.
    let sharedCount: Int
}

enum ContactsService {
    // MARK: Authorization

    static func authorizationState() -> ContactsAuthState {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        // `CNAuthorizationStatus.limited` is iOS 18 only; comparing the raw value keeps
        // this file compiling against the iOS 17 SDK as well.
        if status.rawValue == 4 { return .limited }
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }

    /// Fires the OS prompt. Only ever called from the pre-prompt screen (docs/02 §2).
    @discardableResult
    static func requestAccess() async -> ContactsAuthState {
        let store = CNContactStore()
        _ = try? await store.requestAccess(for: .contacts)
        return authorizationState()
    }

    /// ISO 3166-1 alpha-2 region used as the default when a number has no "+".
    static var region: String {
        (Locale.current.region?.identifier ?? "US").uppercased()
    }

    // MARK: Reading the address book

    /// Reads every contact that has at least one phone number, off the main actor.
    static func fetchAll() async -> [RawContact] {
        await Task.detached(priority: .userInitiated) { () -> [RawContact] in
            var keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            // CNContactFormatter raises if the contact was fetched without its own keys.
            keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))

            let request = CNContactFetchRequest(keysToFetch: keys)
            request.unifyResults = true

            var contacts: [RawContact] = []
            let store = CNContactStore()
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let numbers = contact.phoneNumbers
                        .map { $0.value.stringValue }
                        .filter { !$0.isEmpty }
                    guard !numbers.isEmpty else { return }

                    var name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                    if name.isEmpty {
                        name = [contact.givenName, contact.familyName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                    }
                    if name.isEmpty { name = numbers[0] }
                    contacts.append(RawContact(name: name, numbers: numbers))
                }
            } catch {
                return []
            }
            return contacts
        }.value
    }

    // MARK: Sync

    /// Builds the directory, plans the diff, uploads it. Throws whatever `KithAPI` throws;
    /// the caller only persists `syncedHashes` when this returns.
    static func sync(api: any KithAPI, lastSynced: Set<String>?) async throws -> ContactSyncOutcome {
        let contacts = await fetchAll()
        let isLimited = authorizationState() == .limited
        return try await sync(api: api, lastSynced: lastSynced, contacts: contacts, isLimited: isLimited)
    }

    /// The half of `sync` that never touches `CNContactStore`: normalise, plan, upload.
    /// The address-book read and the authorization check are the caller's, which is what
    /// lets `KithTests` exercise the limited-access rule on a simulator with no contacts
    /// permission (TESTING.md §4.12).
    static func sync(api: any KithAPI, lastSynced: Set<String>?,
                     contacts: [RawContact], isLimited: Bool) async throws -> ContactSyncOutcome {
        let directory = ContactDirectory.build(
            from: contacts,
            normalizer: BasicPhoneNormalizer(),
            region: region
        )
        let plan = ContactSyncPlanner.plan(current: directory.hashes, lastSynced: lastSynced)

        if plan.isEmpty {
            return ContactSyncOutcome(
                directory: directory,
                matches: [],
                friends: [],
                syncedHashes: lastSynced ?? directory.hashes,
                sharedCount: contacts.count
            )
        }

        // Limited access (iOS 18) only ever shows the contacts the user picked, so a
        // hash that is missing from this fetch has not necessarily left the address
        // book. Never send removals and never claim a full sync from a partial view.
        let response = try await api.matchContacts(
            added: plan.added,
            removed: isLimited ? [] : plan.removed,
            full: isLimited ? false : plan.full
        )

        // What the server now holds. A truncated plan (`added` cut to fit one request)
        // means `directory.hashes` overstates it, so the set is derived from what was
        // actually sent — the remainder goes out on the next sync.
        let syncedHashes: Set<String>
        if isLimited {
            syncedHashes = (lastSynced ?? []).union(plan.added)
        } else if plan.full {
            syncedHashes = directory.hashes
        } else {
            syncedHashes = (lastSynced ?? []).subtracting(plan.removed).union(plan.added)
        }

        return ContactSyncOutcome(
            directory: directory,
            matches: response.matches,
            friends: response.friends,
            syncedHashes: syncedHashes,
            sharedCount: contacts.count
        )
    }

    // MARK: Small helpers

    static func relativeTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
