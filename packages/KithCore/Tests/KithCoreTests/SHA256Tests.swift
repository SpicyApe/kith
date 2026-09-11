import XCTest
@testable import KithCore

final class SHA256Tests: XCTestCase {
    // MARK: NIST test vectors, per the doc comment on SHA256.hex.

    func testHexOfABC() {
        XCTAssertEqual(
            SHA256.hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testHexOfEmptyString() {
        XCTAssertEqual(
            SHA256.hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testHexOfOneThousandAs() {
        XCTAssertEqual(
            SHA256.hex(String(repeating: "a", count: 1_000)),
            "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
        )
    }

    // MARK: Format and determinism, at the 55/56/64-byte block-boundary inputs.
    // SHA-256 pads within a 64-byte block; 55 bytes is the largest message that
    // still fits length+padding in one block, 56 just misses it, 64 is a full
    // block on its own — the classic boundary cases for a block-based hash.

    func testDeterminismAndFormatAtBlockBoundaries() {
        for length in [55, 56, 64] {
            let input = String(repeating: "k", count: length)

            let first = SHA256.hex(input)
            let second = SHA256.hex(input)
            XCTAssertEqual(first, second, "digest of a \(length)-byte input must be deterministic")

            XCTAssertEqual(first.count, 64, "hex digest must be 64 characters for a \(length)-byte input")
            XCTAssertTrue(
                first.allSatisfy { "0123456789abcdef".contains($0) },
                "hex digest must be lowercase hex for a \(length)-byte input, got \(first)"
            )
        }
    }

    // MARK: Consistency between `hex` and `digest`.

    func testHexIsConsistentWithDigestOfUTF8Bytes() {
        let text = "+15551234567"
        let bytes = Array(text.utf8)
        let digestHex = SHA256.digest(bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(SHA256.hex(text), digestHex)
    }
}
