import XCTest
@testable import AhkMacCore

final class HotstringEngineTests: XCTestCase {
    private func engine(_ rules: [HotstringRule]) -> HotstringEngine {
        HotstringEngine(rules: rules)
    }

    private func type(_ text: String, into engine: HotstringEngine) -> [Replacement?] {
        text.map { engine.handleCharacter($0) }
    }

    private let btw = HotstringRule(trigger: "btw", replacement: "by the way",
                                    immediate: false, line: 1)
    private let mail = HotstringRule(trigger: "@@", replacement: "user@example.com",
                                     immediate: true, line: 2)

    func testEndCharModeFiresOnEndChar() {
        let engine = engine([btw])
        XCTAssertEqual(type("btw", into: engine), [nil, nil, nil])
        XCTAssertEqual(engine.handleCharacter(" "),
                       Replacement(backspaces: 3, text: "by the way", repostTrigger: true))
    }

    func testEndCharModeDoesNotFireWithoutEndChar() {
        let engine = engine([btw])
        XCTAssertEqual(type("btwx ", into: engine), [nil, nil, nil, nil, nil])
    }

    func testSuffixMatchFiresMidWord() {
        let engine = engine([btw])
        XCTAssertEqual(type("xbtw", into: engine), [nil, nil, nil, nil])
        XCTAssertEqual(engine.handleCharacter("."),
                       Replacement(backspaces: 3, text: "by the way", repostTrigger: true))
    }

    func testImmediateModeFiresOnLastCharacter() {
        let engine = engine([mail])
        XCTAssertEqual(engine.handleCharacter("@"), nil)
        XCTAssertEqual(engine.handleCharacter("@"),
                       Replacement(backspaces: 1, text: "user@example.com", repostTrigger: false))
    }

    func testEndCharWithoutMatchResetsBuffer() {
        let engine = engine([mail])
        _ = type("@", into: engine)
        XCTAssertNil(engine.handleCharacter(" "))
        // buffer was reset, so a single further "@" must not fire
        XCTAssertNil(engine.handleCharacter("@"))
    }

    func testBackspaceRepairsBuffer() {
        let engine = engine([btw])
        _ = type("btx", into: engine)
        engine.handleBackspace()
        XCTAssertNil(engine.handleCharacter("w"))
        XCTAssertEqual(engine.handleCharacter(" ")?.text, "by the way")
    }

    func testLongestTriggerWins() {
        let short = HotstringRule(trigger: "tw", replacement: "SHORT", immediate: false, line: 1)
        let engine = engine([short, btw])
        _ = type("btw", into: engine)
        XCTAssertEqual(engine.handleCharacter(" ")?.text, "by the way")
    }

    func testResetClearsPendingMatch() {
        let engine = engine([btw])
        _ = type("btw", into: engine)
        engine.reset()
        XCTAssertNil(engine.handleCharacter(" "))
    }

    func testFunctionKeyCharacterClearsBuffer() {
        let engine = engine([btw])
        _ = type("bt", into: engine)
        XCTAssertNil(engine.handleCharacter("\u{F704}")) // F1 on macOS
        XCTAssertNil(engine.handleCharacter("w"))
        XCTAssertNil(engine.handleCharacter(" "))
    }

    func testBufferCapKeepsSuffix() {
        let engine = engine([btw])
        _ = type("aaaaaaaaaabtw", into: engine)
        XCTAssertEqual(engine.handleCharacter(" ")?.text, "by the way")
    }

    func testNoRulesNeverFires() {
        let engine = engine([])
        XCTAssertEqual(type("hello world. ", into: engine),
                       Array(repeating: nil, count: 13))
    }

    func testIsTypable() {
        XCTAssertTrue(HotstringEngine.isTypable("a"))
        XCTAssertTrue(HotstringEngine.isTypable("中"))
        XCTAssertTrue(HotstringEngine.isTypable("👍"))
        XCTAssertFalse(HotstringEngine.isTypable("\u{08}"))
        XCTAssertFalse(HotstringEngine.isTypable("\u{F704}"))
    }
}
