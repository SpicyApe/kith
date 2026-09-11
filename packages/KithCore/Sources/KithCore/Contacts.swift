// Contacts.swift — everything about contacts that is not the Contacts framework.
//
// CONTRACT FILE. The app target reads CNContacts and hands (name, rawNumbers) pairs
// here. This file normalises, hashes, diffs against the last sync, and keeps the
// on-device hash → name map. Names never leave this layer. See docs/02 §2, docs/04 §3.

import Foundation

// MARK: SHA-256 (pure Swift; no CryptoKit so this compiles everywhere)

public enum SHA256 {
    /// Lowercase hex digest of the UTF-8 bytes of `text`. Must match `sha256Hex` in
    /// supabase/functions/_shared/hashing.ts (standard FIPS 180-4; e.g. "abc" →
    /// "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad").
    public static func hex(_ text: String) -> String {
        digest(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Digest of arbitrary bytes.
    public static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]

        var message = bytes
        let bitLength = UInt64(bytes.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let base = chunkStart + i * 4
                w[i] = (UInt32(message[base]) << 24)
                    | (UInt32(message[base + 1]) << 16)
                    | (UInt32(message[base + 2]) << 8)
                    | UInt32(message[base + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]

            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ Self.k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                hh = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }

            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }

        var result = [UInt8]()
        result.reserveCapacity(32)
        for value in h {
            result.append(UInt8((value >> 24) & 0xff))
            result.append(UInt8((value >> 16) & 0xff))
            result.append(UInt8((value >> 8) & 0xff))
            result.append(UInt8(value & 0xff))
        }
        return result
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
}

// MARK: Phone normalisation

/// Turns an address-book string into E.164 ("+15551234567") or nil.
///
/// Rules (a deliberately simple subset of libphonenumber, good enough for v1;
/// the app may later swap in PhoneNumberKit behind this same protocol):
/// 1. Strip spaces, dashes, dots, parentheses, and non-breaking spaces.
/// 2. Convert a leading "00" to "+".
/// 3. If it starts with "+": keep the digits; valid when 8...15 digits.
/// 4. Else, using `defaultRegion` (ISO 3166-1 alpha-2, uppercase) look up the calling code in
///    `CallingCodes.table`; if the region is unknown → nil. Drop one leading trunk "0" when
///    `CallingCodes.trunkPrefixRegions` contains the region. For region "US"/"CA" (NANP) a
///    leading "1" on an 11-digit number is the country code, not a trunk prefix.
///    Prefix "+<callingCode>"; valid when the total is 8...15 digits. For NANP regions
///    (calling code "1") the national number must be exactly 10 digits after dropping a
///    leading "1"; anything else → nil.
/// 5. Any remaining non-digit → nil. Extensions ("x123", ";ext=") → strip from the first
///    "x", "X", ";" or "," onward before step 1.
public protocol PhoneNormalizing: Sendable {
    func e164(_ raw: String, defaultRegion: String) -> String?
}

public struct BasicPhoneNormalizer: PhoneNormalizing, Sendable {
    public init() {}
    public func e164(_ raw: String, defaultRegion: String) -> String? {
        // Extensions are stripped before anything else.
        var working = raw
        if let cut = working.firstIndex(where: { $0 == "x" || $0 == "X" || $0 == ";" || $0 == "," }) {
            working = String(working[working.startIndex..<cut])
        }

        // Step 1: strip separators.
        let stripped: Set<Character> = [" ", "-", ".", "(", ")", "\u{00A0}"]
        working = String(working.filter { !stripped.contains($0) })

        // Step 2: leading "00" → "+".
        if working.hasPrefix("00") {
            working = "+" + working.dropFirst(2)
        }

        if working.hasPrefix("+") {
            let digits = String(working.dropFirst())
            guard !digits.isEmpty, digits.allSatisfy(\.isAsciiDigit),
                  (8...15).contains(digits.count) else { return nil }
            return "+" + digits
        }

        guard working.allSatisfy(\.isAsciiDigit), !working.isEmpty else { return nil }

        let region = defaultRegion.uppercased()
        guard let callingCode = CallingCodes.table[region] else { return nil }

        var national = working
        if region == "US" || region == "CA" {
            if national.count == 11 && national.hasPrefix("1") {
                national = String(national.dropFirst())
            }
        } else if CallingCodes.trunkPrefixRegions.contains(region), national.hasPrefix("0") {
            national = String(national.dropFirst())
        }

        if callingCode == "1", national.count != 10 {
            return nil
        }

        let full = callingCode + national
        guard (8...15).contains(full.count) else { return nil }
        return "+" + full
    }
}

private extension Character {
    var isAsciiDigit: Bool { isASCII && isNumber }
}

public enum CallingCodes {
    /// ISO 3166-1 alpha-2 → calling code (digits only, no "+"). Must cover at least every
    /// region iOS can report as `CNContactsUserDefaults.countryCode` / `Locale.region`;
    /// implementers fill in the full ITU list (about 240 entries).
    public static let table: [String: String] = [
        // NANP (all share "1")
        "US": "1", "CA": "1", "AG": "1", "AI": "1", "AS": "1", "BB": "1", "BM": "1", "BS": "1",
        "DM": "1", "DO": "1", "GD": "1", "GU": "1", "JM": "1", "KN": "1", "KY": "1", "LC": "1",
        "MP": "1", "MS": "1", "PR": "1", "SX": "1", "TC": "1", "TT": "1", "VC": "1", "VG": "1", "VI": "1",

        // Zone 7
        "RU": "7", "KZ": "7",

        // Zone 2 — Africa (and a few others)
        "EG": "20",
        "SS": "211", "MA": "212", "DZ": "213", "TN": "216", "LY": "218",
        "GM": "220", "SN": "221", "MR": "222", "ML": "223", "GN": "224", "CI": "225", "BF": "226",
        "NE": "227", "TG": "228", "BJ": "229", "MU": "230", "LR": "231", "SL": "232", "GH": "233",
        "NG": "234", "TD": "235", "CF": "236", "CM": "237", "CV": "238", "ST": "239",
        "GQ": "240", "GA": "241", "CG": "242", "CD": "243", "AO": "244", "GW": "245", "IO": "246",
        "AC": "247", "SC": "248", "SD": "249",
        "RW": "250", "ET": "251", "SO": "252", "DJ": "253", "KE": "254", "TZ": "255", "UG": "256", "BI": "257",
        "MZ": "258",
        "ZM": "260", "MG": "261", "RE": "262", "YT": "262", "ZW": "263", "NA": "264", "MW": "265",
        "LS": "266", "BW": "267", "SZ": "268", "KM": "269",
        "ZA": "27",
        "SH": "290", "ER": "291", "AW": "297", "FO": "298", "GL": "299",

        // Zone 3 — Europe
        "GR": "30", "NL": "31", "BE": "32", "FR": "33", "ES": "34",
        "GI": "350", "PT": "351", "LU": "352", "IE": "353", "IS": "354", "AL": "355", "MT": "356",
        "CY": "357", "FI": "358", "AX": "358", "BG": "359",
        "HU": "36",
        "LT": "370", "LV": "371", "EE": "372", "MD": "373", "AM": "374", "BY": "375", "AD": "376",
        "MC": "377", "SM": "378", "VA": "379",
        "UA": "380", "RS": "381", "ME": "382", "XK": "383", "HR": "385", "SI": "386", "BA": "387",
        "MK": "389",
        "IT": "39",
        "RO": "40",
        "CH": "41",
        "CZ": "420", "SK": "421", "LI": "423",
        "AT": "43",
        "GB": "44", "GG": "44", "JE": "44", "IM": "44",
        "DK": "45",
        "SE": "46",
        "NO": "47", "SJ": "47",
        "PL": "48",
        "DE": "49",

        // Zone 5 — Americas (Central/South, non-NANP)
        "FK": "500", "BZ": "501", "GT": "502", "SV": "503", "HN": "504", "NI": "505", "CR": "506",
        "PA": "507", "PM": "508", "HT": "509",
        "PE": "51", "MX": "52", "CU": "53", "AR": "54", "BR": "55", "CL": "56", "CO": "57", "VE": "58",
        "GP": "590", "BL": "590", "MF": "590",
        "BO": "591", "GY": "592", "EC": "593", "GF": "594", "PY": "595", "MQ": "596", "SR": "597",
        "UY": "598",
        "CW": "599", "BQ": "599",

        // Zone 6 — Southeast Asia / Oceania
        "MY": "60", "AU": "61", "CX": "61", "CC": "61", "ID": "62", "PH": "63", "NZ": "64", "SG": "65",
        "TH": "66",
        "TL": "670", "NF": "672", "BN": "673", "NR": "674", "PG": "675", "TO": "676", "SB": "677",
        "VU": "678", "FJ": "679",
        "PW": "680", "WF": "681", "CK": "682", "NU": "683", "WS": "685", "KI": "686", "NC": "687",
        "TV": "688", "PF": "689", "TK": "690", "FM": "691", "MH": "692",

        // Zone 8 — East Asia
        "JP": "81", "KR": "82", "VN": "84",
        "KP": "850", "HK": "852", "MO": "853", "KH": "855", "LA": "856",
        "CN": "86",
        "BD": "880", "TW": "886",

        // Zone 9 — South/West Asia, Middle East
        "TR": "90", "IN": "91", "PK": "92", "AF": "93", "LK": "94", "MM": "95",
        "MV": "960", "LB": "961", "JO": "962", "SY": "963", "IQ": "964", "KW": "965", "SA": "966",
        "YE": "967", "OM": "968", "PS": "970", "AE": "971", "IL": "972", "BH": "973", "QA": "974",
        "BT": "975", "MN": "976", "NP": "977",
        "IR": "98",
        "TJ": "992", "TM": "993", "AZ": "994", "GE": "995", "KG": "996", "UZ": "998",
    ]

    /// Regions whose domestic numbers carry a leading trunk "0" that must be dropped
    /// (GB, DE, FR, IT, ES, NL, BE, AT, CH, SE, NO, DK, FI, PL, IE, AU, NZ, ZA, IN, PK, BD,
    /// ID, TR, JP, KR, TW, VN, TH, MY, PH, KE, NG, GH, EG, IL, AR, BR, CL, PE, CO ...
    /// implementers complete this from the ITU trunk-prefix list).
    public static let trunkPrefixRegions: Set<String> = [
        // Western / Northern / Central / Eastern Europe
        "GB", "GG", "JE", "IM", "DE", "FR", "IT", "ES", "NL", "BE", "AT", "CH", "SE", "NO", "DK",
        "FI", "PL", "IE", "PT", "GR", "HU", "RO", "CZ", "SK", "BG", "HR", "SI", "RS", "BA", "ME",
        "MK", "AL", "LT", "LV", "EE", "MD", "UA", "LU", "BY",

        // Asia-Pacific
        "AU", "NZ", "IN", "PK", "BD", "ID", "TR", "JP", "KR", "TW", "VN", "TH", "MY", "PH", "KH",
        "LA", "MN", "NP", "LK", "MM", "CN",

        // Africa
        "ZA", "KE", "NG", "GH", "EG", "TZ", "UG", "ZM", "ZW", "MZ", "NA", "BW", "RW", "ET", "SN",
        "CI", "CM", "DZ", "MA", "TN", "LY", "SD",

        // Middle East
        "IL", "JO", "LB", "SY", "IQ", "SA", "YE", "IR",

        // Latin America (only the regions the spec calls out explicitly; NOT MX)
        "AR", "BR", "CL", "PE", "CO", "UY",
    ]
}

// MARK: Hashing and the local directory

public struct RawContact: Sendable, Equatable, Hashable {
    /// Display name from the address book ("Mom", "Dev from work").
    public let name: String
    public let numbers: [String]
    public init(name: String, numbers: [String]) {
        self.name = name
        self.numbers = numbers
    }
}

/// On-device map from sha256(E.164) → display name. Never uploaded. Persisted by the app
/// (as JSON) and rebuilt on every sync.
public struct ContactDirectory: Codable, Sendable, Equatable {
    public private(set) var namesByHash: [String: String]
    public init(namesByHash: [String: String] = [:]) { self.namesByHash = namesByHash }

    /// Builds the directory from raw contacts: every number is normalised with `normalizer`
    /// and `region`; unparseable numbers are skipped; when two contacts share a number the
    /// first name (in input order) wins. Hashes are `SHA256.hex(e164)`.
    public static func build(from contacts: [RawContact], normalizer: PhoneNormalizing, region: String) -> ContactDirectory {
        var namesByHash: [String: String] = [:]
        for contact in contacts {
            for rawNumber in contact.numbers {
                guard let e164 = normalizer.e164(rawNumber, defaultRegion: region) else { continue }
                let hash = SHA256.hex(e164)
                if namesByHash[hash] == nil {
                    namesByHash[hash] = contact.name
                }
            }
        }
        return ContactDirectory(namesByHash: namesByHash)
    }

    public var hashes: Set<String> { Set(namesByHash.keys) }
    public func name(forHash h: String) -> String? { namesByHash[h] }
}

/// What to send to `match-contacts`.
public struct SyncPlan: Sendable, Equatable {
    public let added: [String]
    public let removed: [String]
    public let full: Bool
    public init(added: [String], removed: [String], full: Bool) {
        self.added = added; self.removed = removed; self.full = full
    }
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && !full }
}

public enum ContactSyncPlanner {
    /// - `lastSynced == nil` (never synced) → full sync with every current hash.
    /// - Otherwise a diff: `added` = current − last, `removed` = last − current, `full` false.
    /// - If the diff would exceed `maxPerRequest` (5,000) in added + removed, fall back to a full sync
    ///   (the server allows one per hour) only if current.count ≤ maxPerRequest; else truncate `added`
    ///   to the first `maxPerRequest − removed.count` sorted hashes (the remainder goes next sync).
    /// Arrays are sorted lexicographically for determinism.
    public static func plan(current: Set<String>, lastSynced: Set<String>?, maxPerRequest: Int = 5_000) -> SyncPlan {
        guard let lastSynced else {
            return SyncPlan(added: current.sorted(), removed: [], full: true)
        }

        let added = current.subtracting(lastSynced)
        let removed = lastSynced.subtracting(current)

        guard added.count + removed.count > maxPerRequest else {
            return SyncPlan(added: added.sorted(), removed: removed.sorted(), full: false)
        }

        if current.count <= maxPerRequest {
            return SyncPlan(added: current.sorted(), removed: [], full: true)
        }

        let sortedRemoved = removed.sorted()
        let keepCount = max(0, maxPerRequest - sortedRemoved.count)
        let truncatedAdded = Array(added.sorted().prefix(keepCount))
        return SyncPlan(added: truncatedAdded, removed: sortedRemoved, full: false)
    }
}

/// Resolves the name to show for a matched friend: the address-book name if the
/// match echoed a hash we know, else the server display name.
public enum FriendNames {
    public static func displayName(for friend: Friend, matches: [MatchedContact], directory: ContactDirectory) -> String {
        if let match = matches.first(where: { $0.userId == friend.userId }),
           let localName = directory.name(forHash: match.hash) {
            return localName
        }
        return friend.displayName
    }
}
