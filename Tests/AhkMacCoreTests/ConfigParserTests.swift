import XCTest
@testable import AhkMacCore

final class ConfigParserTests: XCTestCase {

    func testFullExample() throws {
        let config = try ConfigParser.parse("""
        # vim arrows
        opt+j :: down
        opt+k :: up

        opt+d :: cmd+right   # end of line
        "btw" => "by the way"
        *"@@" => "user@example.com"
        """)
        XCTAssertEqual(config.keymaps, [
            KeymapRule(source: Chord(keyCode: 0x26, modifiers: [.opt]),
                       target: Chord(keyCode: 0x7D, modifiers: []), line: 2),
            KeymapRule(source: Chord(keyCode: 0x28, modifiers: [.opt]),
                       target: Chord(keyCode: 0x7E, modifiers: []), line: 3),
            KeymapRule(source: Chord(keyCode: 0x02, modifiers: [.opt]),
                       target: Chord(keyCode: 0x7C, modifiers: [.cmd]), line: 5),
        ])
        XCTAssertEqual(config.hotstrings, [
            HotstringRule(trigger: "btw", replacement: "by the way", immediate: false, line: 6),
            HotstringRule(trigger: "@@", replacement: "user@example.com", immediate: true, line: 7),
        ])
    }

    func testEmptyAndCommentOnlyConfig() throws {
        let config = try ConfigParser.parse("\n# nothing here\n   \n")
        XCTAssertEqual(config, Config(keymaps: [], hotstrings: []))
    }

    func testErrorLineNumbers() {
        XCTAssertThrowsError(try ConfigParser.parse("opt+j :: down\nopt+x :: bogus\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 2, message: "unknown key 'bogus'"))
        }
    }

    func testUnrecognizedLine() {
        XCTAssertThrowsError(try ConfigParser.parse("hello world")) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 1)
        }
    }

    func testDoubleSeparatorRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("a :: b :: c")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "expected exactly one '::'"))
        }
    }

    func testDuplicateKeymapRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("opt+j :: down\nopt+j :: up\n")) {
            XCTAssertEqual($0 as? ConfigError,
                           ConfigError(line: 2, message: "duplicate keymap source (first defined on line 1)"))
        }
    }

    func testDuplicateTriggerRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("\"x\" => \"a\"\n*\"x\" => \"b\"\n")) {
            XCTAssertEqual($0 as? ConfigError,
                           ConfigError(line: 2, message: "duplicate trigger \"x\" (first defined on line 1)"))
        }
    }

    func testHotstringSyntaxErrors() {
        XCTAssertThrowsError(try ConfigParser.parse("\"x\" -> \"y\"")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "expected '=>' after trigger"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("\"x\" => \"y\" z")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "unexpected content after replacement"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("\"\" => \"y\"")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "empty trigger"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("\"a b\" => \"y\"")) {
            XCTAssertEqual($0 as? ConfigError,
                           ConfigError(line: 1, message: "trigger must not contain whitespace"))
        }
    }

    func testUnescapedEndCharInTriggerRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("\"e-mail\" => \"y\"")) {
            XCTAssertEqual($0 as? ConfigError,
                           ConfigError(line: 1, message: "unescaped end character '-' in trigger (write '\\-')"))
        }
    }

    func testEscapedEndCharInTriggerAccepted() throws {
        let config = try ConfigParser.parse(#""e\-mail" => "yuan@example.com""#)
        XCTAssertEqual(config.hotstrings.first?.trigger, "e-mail")

        let immediate = try ConfigParser.parse(#"*"btw\." => "by the way.""#)
        XCTAssertEqual(immediate.hotstrings.first,
                       HotstringRule(trigger: "btw.", replacement: "by the way.",
                                     immediate: true, line: 1))
    }

    func testStarWithoutQuoteRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("*btw => \"y\"")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "expected opening quote"))
        }
    }

    func testReplacementMayContainAnything() throws {
        let config = try ConfigParser.parse(#""sig" => "Bye!\n-- yt :: #1""#)
        XCTAssertEqual(config.hotstrings.first?.replacement, "Bye!\n-- yt :: #1")
    }
}
