import XCTest
@testable import AhkMacCore

private extension Firing {
    /// Convenience accessor mirroring the old `Replacement.text` field, for
    /// assertions that only care about the fired text.
    var text: String? {
        if case .text(let text, _) = output { return text }
        return nil
    }
}

final class HotstringEngineTests: XCTestCase {
    private func engine(_ rules: [HotstringRule]) -> HotstringEngine {
        HotstringEngine(rules: rules)
    }

    private func type(_ text: String, into engine: HotstringEngine) -> [Firing?] {
        text.map { engine.handleCharacter($0) }
    }

    private let btw = HotstringRule(trigger: "btw", action: .text("by the way"),
                                    immediate: false, scope: .global, line: 1)
    private let mail = HotstringRule(trigger: "@@", action: .text("user@example.com"),
                                     immediate: true, scope: .global, line: 2)

    func testEndCharModeFiresOnEndChar() {
        let engine = engine([btw])
        XCTAssertEqual(type("btw", into: engine), [nil, nil, nil])
        XCTAssertEqual(engine.handleCharacter(" "),
                       Firing(backspaces: 3, output: .text("by the way", repost: true)))
    }

    func testEndCharModeDoesNotFireWithoutEndChar() {
        let engine = engine([btw])
        XCTAssertEqual(type("btwx ", into: engine), [nil, nil, nil, nil, nil])
    }

    func testSuffixMatchFiresMidWord() {
        let engine = engine([btw])
        XCTAssertEqual(type("xbtw", into: engine), [nil, nil, nil, nil])
        XCTAssertEqual(engine.handleCharacter("."),
                       Firing(backspaces: 3, output: .text("by the way", repost: true)))
    }

    func testImmediateModeFiresOnLastCharacter() {
        let engine = engine([mail])
        XCTAssertEqual(engine.handleCharacter("@"), nil)
        XCTAssertEqual(engine.handleCharacter("@"),
                       Firing(backspaces: 1, output: .text("user@example.com", repost: false)))
    }

    func testEndCharDoesNotCompleteSplitImmediateTrigger() {
        let engine = engine([mail])
        _ = type("@", into: engine)
        XCTAssertNil(engine.handleCharacter(" "))
        // the space sits between the two @s in the buffer, so no fire
        XCTAssertNil(engine.handleCharacter("@"))
    }

    func testPunctuationInsideTrigger() {
        let email = HotstringRule(trigger: "e-mail", action: .text("yuan@example.com"),
                                  immediate: false, scope: .global, line: 1)
        let engine = engine([email])
        XCTAssertEqual(type("e-mail", into: engine), Array(repeating: nil, count: 6))
        XCTAssertEqual(engine.handleCharacter(" "),
                       Firing(backspaces: 6, output: .text("yuan@example.com", repost: true)))
    }

    func testImmediateTriggerEndingInPunctuation() {
        let dotted = HotstringRule(trigger: "btw.", action: .text("by the way."),
                                   immediate: true, scope: .global, line: 1)
        let engine = engine([dotted])
        _ = type("btw", into: engine)
        XCTAssertEqual(engine.handleCharacter("."),
                       Firing(backspaces: 3, output: .text("by the way.", repost: false)))
    }

    func testEndCharModeWinsOverImmediateOnSameKeystroke() {
        let immediateTw = HotstringRule(trigger: "tw.", action: .text("IMMEDIATE"),
                                        immediate: true, scope: .global, line: 2)
        let engine = engine([btw, immediateTw])
        _ = type("btw", into: engine)
        XCTAssertEqual(engine.handleCharacter("."),
                       Firing(backspaces: 3, output: .text("by the way", repost: true)))
    }

    func testBackspaceRepairsBufferAcrossEndChar() {
        let engine = engine([btw])
        _ = type("bt.", into: engine)
        engine.handleBackspace()
        XCTAssertNil(engine.handleCharacter("w"))
        XCTAssertEqual(engine.handleCharacter(" ")?.text, "by the way")
    }

    func testBackspaceRepairsBuffer() {
        let engine = engine([btw])
        _ = type("btx", into: engine)
        engine.handleBackspace()
        XCTAssertNil(engine.handleCharacter("w"))
        XCTAssertEqual(engine.handleCharacter(" ")?.text, "by the way")
    }

    func testLongestTriggerWins() {
        let short = HotstringRule(trigger: "tw", action: .text("SHORT"), immediate: false, scope: .global, line: 1)
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

    // MARK: app scopes

    func testScopeFiltersTriggers() {
        let engine = HotstringEngine(rules: [
            HotstringRule(trigger: "gm", action: .text("gmail.com"), immediate: true,
                          scope: .apps(["com.google.chrome"]), line: 1),
        ])
        engine.setActiveApp("com.apple.mail")
        for ch in "gm" { XCTAssertNil(engine.handleCharacter(ch)) }   // 不在 Chrome,不触发
        engine.setActiveApp("com.google.chrome")
        for ch in "g" { XCTAssertNil(engine.handleCharacter(ch)) }
        XCTAssertEqual(engine.handleCharacter("m"),
                       Firing(backspaces: 1, output: .text("gmail.com", repost: false)))
    }

    func testAppSwitchClearsBuffer() {
        let engine = HotstringEngine(rules: [
            HotstringRule(trigger: "btw", action: .text("by the way"), immediate: true, scope: .global, line: 1),
        ])
        engine.setActiveApp("com.a.b")
        for ch in "bt" { XCTAssertNil(engine.handleCharacter(ch)) }
        engine.setActiveApp("com.c.d")                                // 切换应用
        XCTAssertNil(engine.handleCharacter("w"))                     // 缓冲已清,不触发
        engine.setActiveApp("COM.C.D")
        XCTAssertNil(engine.handleCharacter("x"))                     // 仅大小写差异,不算切换 —— 缓冲保留
    }

    func testSpecificScopeBeatsGlobalOnSameTrigger() {
        let engine = HotstringEngine(rules: [
            HotstringRule(trigger: "sig", action: .text("global"), immediate: true, scope: .global, line: 1),
            HotstringRule(trigger: "sig", action: .text("chrome"), immediate: true,
                          scope: .apps(["com.google.chrome"]), line: 2),
        ])
        engine.setActiveApp("com.google.chrome")
        for ch in "si" { XCTAssertNil(engine.handleCharacter(ch)) }
        XCTAssertEqual(engine.handleCharacter("g"),
                       Firing(backspaces: 2, output: .text("chrome", repost: false)))
    }

    func testLongerTriggerStillBeatsScopeTier() {
        let engine = HotstringEngine(rules: [
            HotstringRule(trigger: "sig", action: .text("chrome"), immediate: true,
                          scope: .apps(["com.google.chrome"]), line: 1),
            HotstringRule(trigger: "absig", action: .text("global"), immediate: true, scope: .global, line: 2),
        ])
        engine.setActiveApp("com.google.chrome")
        for ch in "absi" { XCTAssertNil(engine.handleCharacter(ch)) }
        XCTAssertEqual(engine.handleCharacter("g"),
                       Firing(backspaces: 4, output: .text("global", repost: false)))
    }

    // MARK: macro targets

    func testMacroHotstringImmediate() {
        let engine = HotstringEngine(rules: [
            HotstringRule(trigger: "@sig", action: .macro(0), immediate: true, scope: .global, line: 1),
        ])
        for ch in "@si" { XCTAssertNil(engine.handleCharacter(ch)) }
        XCTAssertEqual(engine.handleCharacter("g"),
                       Firing(backspaces: 3, output: .macro(0)))   // len-1,最后一击被吞
    }

    func testMacroHotstringEndCharSwallowsEndChar() {
        let engine = HotstringEngine(rules: [
            HotstringRule(trigger: "sig", action: .macro(2), immediate: false, scope: .global, line: 1),
        ])
        for ch in "sig" { XCTAssertNil(engine.handleCharacter(ch)) }
        XCTAssertEqual(engine.handleCharacter(" "),
                       Firing(backspaces: 3, output: .macro(2)))   // 结束符不重放:output 非 .text,无 repost
    }
}
