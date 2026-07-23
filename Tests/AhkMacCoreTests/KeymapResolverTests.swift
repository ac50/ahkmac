import XCTest
@testable import AhkMacCore

final class KeymapResolverTests: XCTestCase {
    private func rule(_ source: Chord, _ target: Chord, line: Int = 1) -> KeymapRule {
        KeymapRule(source: source, target: target, line: line)
    }

    func testExactMatch() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let resolver = KeymapResolver(rules: [optJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt]), optJ)
        XCTAssertNil(resolver.resolve(keyCode: 0x26, pressed: []))
        XCTAssertNil(resolver.resolve(keyCode: 0x26, pressed: [.cmd]))
        XCTAssertNil(resolver.resolve(keyCode: 0x28, pressed: [.opt]))
    }

    func testSubsetMatchAllowsExtraModifiers() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let resolver = KeymapResolver(rules: [optJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt, .shift]), optJ)
    }

    func testMostSpecificRuleWins() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let optShiftJ = rule(Chord(keyCode: 0x26, modifiers: [.opt, .shift]),
                             Chord(keyCode: 0x79, modifiers: []), line: 2)
        let resolver = KeymapResolver(rules: [optJ, optShiftJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt, .shift]), optShiftJ)
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt]), optJ)
    }

    func testTieGoesToFirstDefined() {
        let optJ = rule(Chord(keyCode: 0x26, modifiers: [.opt]),
                        Chord(keyCode: 0x7D, modifiers: []))
        let shiftJ = rule(Chord(keyCode: 0x26, modifiers: [.shift]),
                          Chord(keyCode: 0x7E, modifiers: []), line: 2)
        let resolver = KeymapResolver(rules: [optJ, shiftJ])
        XCTAssertEqual(resolver.resolve(keyCode: 0x26, pressed: [.opt, .shift]), optJ)
    }

    func testBareKeyRuleMatchesWithAnyModifiers() {
        let aToB = rule(Chord(keyCode: 0x00, modifiers: []),
                        Chord(keyCode: 0x0B, modifiers: []))
        let resolver = KeymapResolver(rules: [aToB])
        XCTAssertEqual(resolver.resolve(keyCode: 0x00, pressed: [.cmd]), aToB)
        XCTAssertEqual(aToB.output(pressed: [.cmd]), Chord(keyCode: 0x0B, modifiers: [.cmd]))
    }
}
