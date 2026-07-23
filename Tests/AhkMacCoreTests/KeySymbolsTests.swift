import XCTest
@testable import AhkMacCore

final class KeySymbolsTests: XCTestCase {
    func testWellKnownCodes() {
        XCTAssertEqual(KeySymbols.keyNames["a"], 0x00)
        XCTAssertEqual(KeySymbols.keyNames["j"], 0x26)
        XCTAssertEqual(KeySymbols.keyNames["down"], 0x7D)
        XCTAssertEqual(KeySymbols.keyNames["up"], 0x7E)
        XCTAssertEqual(KeySymbols.keyNames["left"], 0x7B)
        XCTAssertEqual(KeySymbols.keyNames["right"], 0x7C)
        XCTAssertEqual(KeySymbols.keyNames["space"], 0x31)
        XCTAssertEqual(KeySymbols.keyNames["delete"], 0x33)
        XCTAssertEqual(KeySymbols.keyNames["esc"], 0x35)
        XCTAssertEqual(KeySymbols.keyNames["grave"], 0x32)
        XCTAssertEqual(KeySymbols.keyNames["f1"], 0x7A)
        XCTAssertEqual(KeySymbols.keyNames["f20"], 0x5A)
    }

    func testAliases() {
        XCTAssertEqual(KeySymbols.keyNames["enter"], KeySymbols.keyNames["return"])
        XCTAssertEqual(KeySymbols.modifierNames["alt"], KeySymbols.modifierNames["opt"])
    }

    func testNoAccidentalDuplicateCodes() {
        // enter/return is the only intended key alias pair.
        XCTAssertEqual(Set(KeySymbols.keyNames.values).count, KeySymbols.keyNames.count - 1)
        // alt/opt is the only intended modifier alias pair.
        XCTAssertEqual(Set(KeySymbols.modifierNames.values).count, KeySymbols.modifierNames.count - 1)
    }

    func testModifierCount() {
        XCTAssertEqual(Modifiers([.cmd, .shift]).count, 2)
        XCTAssertEqual(Modifiers([]).count, 0)
    }
}
