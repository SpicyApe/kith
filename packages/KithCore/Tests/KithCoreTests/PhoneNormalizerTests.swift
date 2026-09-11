import XCTest
@testable import KithCore

final class PhoneNormalizerTests: XCTestCase {
    private let normalizer = BasicPhoneNormalizer()

    private func assertE164(
        _ raw: String,
        region: String,
        _ expected: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            normalizer.e164(raw, defaultRegion: region),
            expected,
            "e164(\(raw.debugDescription), defaultRegion: \(region.debugDescription))",
            file: file,
            line: line
        )
    }

    func testTableDrivenCases() {
        // Already-international, with formatting to strip.
        assertE164("+1 555 123 4567", region: "US", "+15551234567")

        // Domestic US formatting, no leading "1".
        assertE164("(555) 123-4567", region: "US", "+15551234567")

        // Domestic US formatting with the NANP country code already present as a
        // leading "1" on an 11-digit number — not a trunk prefix, must not be
        // doubled by also prefixing "+1".
        assertE164("1 (555) 123-4567", region: "US", "+15551234567")

        // GB: leading trunk "0" must be dropped before prefixing the calling code.
        assertE164("020 7946 0958", region: "GB", "+442079460958")

        // NOTE: "+44 (0)20 7946 0958" (a "+" number with an embedded trunk zero) is
        // intentionally not covered — the contract doesn't require handling that.

        // AU: same trunk-stripping shape as GB, different calling code.
        assertE164("0412 345 678", region: "AU", "+61412345678")

        // Leading "00" converts to "+"; the defaultRegion is then irrelevant because
        // the number is already international.
        assertE164("00 44 20 7946 0958", region: "US", "+442079460958")

        // DE: trunk-stripped domestic number.
        assertE164("030 12345678", region: "DE", "+493012345678")

        // FR/GB/DE mobile numbers as the address book usually stores them: spaces as
        // separators and the national trunk "0", which must be dropped before the
        // calling code is prefixed.
        assertE164("06 12 34 56 78", region: "FR", "+33612345678")
        assertE164("07911 123456", region: "GB", "+447911123456")
        assertE164("0151 23456789", region: "DE", "+4915123456789")

        // Too short even after prefixing the US calling code (7 raw digits).
        assertE164("555-1234", region: "US", nil)

        // Too long: more than 15 digits after the "+".
        assertE164("+123456789012345678", region: "US", nil)

        // No digits at all.
        assertE164("abc", region: "US", nil)

        // Extensions are stripped from the first "x"/"X"/";"/"," onward.
        assertE164("+1 555 123 4567 x89", region: "US", "+15551234567")
        assertE164("+1 555 123 4567,,89", region: "US", "+15551234567")

        // RU: documents a real limitation of this simple algorithm — the rules only
        // strip a leading trunk "0", never a leading "8" (Russia's domestic trunk
        // prefix), so the "8" survives as a regular digit and gets the "+7" calling
        // code prepended in front of it, producing a 13-digit number that is NOT the
        // correct E.164 form. This is intentional per the contract and asserted here
        // to document, not endorse, the limitation.
        assertE164("8 (495) 123-45-67", region: "RU", "+784951234567")

        // Unknown region, not a "+" number → nil.
        assertE164("0412 345 678", region: "ZZ", nil)

        // Unknown region, but the number is already a "+" number → region is ignored.
        assertE164("+15551234567", region: "ZZ", "+15551234567")
    }
}
