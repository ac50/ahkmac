import XCTest
@testable import AhkMacCore

final class KeymapResolverTests: XCTestCase {
    private func rule(_ source: Chord, _ target: Chord, line: Int = 1) -> KeymapRule {
        KeymapRule(source: source, target: .chord(target), scope: .global, line: line)
    }

    func testExactMatch() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let resolver = KeymapResolver(rules: [optJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt], app: nil), optJ)
        XCTAssertNil(resolver.resolve(keyCode: 0x26, pressed: [], app: nil))
        XCTAssertNil(resolver.resolve(keyCode: 0x26, pressed: [.cmd], app: nil))
        XCTAssertNil(resolver.resolve(keyCode: 0x28, pressed: [.opt], app: nil))
    }

    func testSubsetMatchAllowsExtraModifiers() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let resolver = KeymapResolver(rules: [optJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt, .shift], app: nil), optJ)
    }

    func testMostSpecificRuleWins() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let optShiftJ = rule(Chord(keyCode: 0x26, modifiers: [.opt, .shift]),
                             Chord(keyCode: 0x79, modifiers: []), line: 2)
        let resolver = KeymapResolver(rules: [optJ, optShiftJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt, .shift], app: nil), optShiftJ)
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt], app: nil), optJ)
    }

    func testTieGoesToFirstDefined() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let shiftJ = rule(Chord(keyCode: 0x26, modifiers: [.shift]),
                          Chord(keyCode: 0x7E, modifiers: []), line: 2)
        let resolver = KeymapResolver(rules: [optJ, shiftJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt, .shift], app: nil), optJ)
    }

    func testBareKeyRuleMatchesWithAnyModifiers() {
        let aToB = rule(Chord(keyCode: 0x00, modifiers: []),
                        Chord(keyCode: 0x0B, modifiers: []))
        let resolver = KeymapResolver(rules: [aToB])
        XCTAssertEqual(resolver.resolve(keyCode: 0x00, pressed: [.cmd], app: nil), aToB)
        XCTAssertEqual(aToB.chordOutput(pressed: [.cmd]), Chord(keyCode: 0x0B, modifiers: [.cmd]))
    }

    func testScopeFiltering() {
        let chrome = KeymapRule(source: Chord(keyCode: 38, modifiers: [.opt]),
                                target: .chord(Chord(keyCode: 126, modifiers: [])),
                                scope: .apps(["com.google.chrome"]), line: 1)
        let resolver = KeymapResolver(rules: [chrome])
        XCTAssertEqual(resolver.resolve(keyCode: 38, pressed: [.opt], app: "com.google.chrome"), chrome)
        XCTAssertEqual(resolver.resolve(keyCode: 38, pressed: [.opt], app: "COM.Google.Chrome"), chrome)
        XCTAssertNil(resolver.resolve(keyCode: 38, pressed: [.opt], app: "com.apple.mail"))
        XCTAssertNil(resolver.resolve(keyCode: 38, pressed: [.opt], app: nil))
    }

    func testScopeTierBreaksTies() {
        let global = KeymapRule(source: Chord(keyCode: 38, modifiers: [.opt]),
                                target: .chord(Chord(keyCode: 125, modifiers: [])), scope: .global, line: 1)
        let except = KeymapRule(source: Chord(keyCode: 38, modifiers: [.opt]),
                                target: .chord(Chord(keyCode: 124, modifiers: [])),
                                scope: .exceptApps(["com.x.y"]), line: 2)
        let chrome = KeymapRule(source: Chord(keyCode: 38, modifiers: [.opt]),
                                target: .chord(Chord(keyCode: 126, modifiers: [])),
                                scope: .apps(["com.google.chrome"]), line: 3)
        let resolver = KeymapResolver(rules: [global, except, chrome])
        XCTAssertEqual(resolver.resolve(keyCode: 38, pressed: [.opt], app: "com.google.chrome"), chrome)
        XCTAssertEqual(resolver.resolve(keyCode: 38, pressed: [.opt], app: "com.apple.mail"), except)
        XCTAssertEqual(resolver.resolve(keyCode: 38, pressed: [.opt], app: "com.x.y"), global)
    }

    func testModifierCountStillBeatsScopeTier() {
        let scopedLoose = KeymapRule(source: Chord(keyCode: 38, modifiers: [.opt]),
                                     target: .chord(Chord(keyCode: 126, modifiers: [])),
                                     scope: .apps(["com.a.b"]), line: 1)
        let globalTight = KeymapRule(source: Chord(keyCode: 38, modifiers: [.opt, .shift]),
                                     target: .chord(Chord(keyCode: 125, modifiers: [])), scope: .global, line: 2)
        let resolver = KeymapResolver(rules: [scopedLoose, globalTight])
        XCTAssertEqual(resolver.resolve(keyCode: 38, pressed: [.opt, .shift], app: "com.a.b"), globalTight)
    }
}
