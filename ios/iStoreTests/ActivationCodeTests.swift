import XCTest
@testable import iStore

final class ActivationCodeTests: XCTestCase {
    func testNormalizeRemovesSeparatorsAndUppercases() {
        XCTAssertEqual(ActivationCode.normalize("demo-demo-0001"), "DEMODEMO0001")
        XCTAssertEqual(ActivationCode.normalize(" abcd efgh\tjklm "), "ABCDEFGHJKLM")
        XCTAssertEqual(ActivationCode.normalize("ab—cd_ef.gh"), "ABCDEFGH")
    }

    func testNormalizeDropsNonLatinCharacters() {
        XCTAssertEqual(ActivationCode.normalize("дemo1"), "EMO1")
        XCTAssertEqual(ActivationCode.normalize(""), "")
    }

    func testFormatGroupsByFour() {
        XCTAssertEqual(ActivationCode.format("demodemo0001"), "DEMO-DEMO-0001")
        XCTAssertEqual(ActivationCode.format("DEMO-DEMO-0001"), "DEMO-DEMO-0001")
        XCTAssertEqual(ActivationCode.format("ab"), "AB")
        XCTAssertEqual(ActivationCode.format("abcd"), "ABCD")
        XCTAssertEqual(ActivationCode.format("abcde"), "ABCD-E")
    }

    func testFormatTruncatesToTwelveCharacters() {
        XCTAssertEqual(ActivationCode.format("ABCDEFGHJKLMNOP"), "ABCD-EFGH-JKLM")
    }

    func testIsComplete() {
        XCTAssertTrue(ActivationCode.isComplete("DEMO-DEMO-0001"))
        XCTAssertTrue(ActivationCode.isComplete("demo demo 0001"))
        XCTAssertFalse(ActivationCode.isComplete("DEMO-DEMO-000"))
        XCTAssertFalse(ActivationCode.isComplete("DEMO-DEMO-00011"))
    }

    func testOSVersionComparison() {
        XCTAssertTrue(OSVersion.isSatisfied(current: "17.4.1", required: "15.0"))
        XCTAssertTrue(OSVersion.isSatisfied(current: "15.0", required: "15"))
        XCTAssertTrue(OSVersion.isSatisfied(current: "16.10", required: "16.9"))
        XCTAssertFalse(OSVersion.isSatisfied(current: "15.7", required: "16.0"))
        XCTAssertEqual(OSVersion.compare("18.1", "18.1.0"), .orderedSame)
    }
}
