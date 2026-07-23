import XCTest
@testable import AhkMacCore

final class ConfigParserHelperTests: XCTestCase {

    // MARK: stripComment

    func testStripCommentOutsideQuotes() {
        XCTAssertEqual(ConfigParser.stripComment("opt+j :: down # vim"), "opt+j :: down ")
        XCTAssertEqual(ConfigParser.stripComment("# whole line"), "")
        XCTAssertEqual(ConfigParser.stripComment("no comment"), "no comment")
    }

    func testHashInsideQuotesIsKept() {
        XCTAssertEqual(ConfigParser.stripComment("\"a#b\" => \"c\" # real"),
                       "\"a#b\" => \"c\" ")
    }

    func testHashAfterEscapedQuoteInsideString() {
        // The escaped quote must not close the string early.
        // (##-delimited raw string: the content itself contains the "# sequence.)
        XCTAssertEqual(ConfigParser.stripComment(##""a\"#b" => "c""##), ##""a\"#b" => "c""##)
    }

    // MARK: trim

    func testTrim() {
        XCTAssertEqual(ConfigParser.trim("  x\t\r"), "x")
        XCTAssertEqual(ConfigParser.trim(""), "")
        XCTAssertEqual(ConfigParser.trimLeading("  x  "), "x  ")
    }

    // MARK: parseQuoted

    func testParseQuotedPlain() throws {
        let (value, rest) = try ConfigParser.parseQuoted("\"btw\" => …", lineNo: 1)
        XCTAssertEqual(value, "btw")
        XCTAssertEqual(rest, " => …")
    }

    func testParseQuotedEscapes() throws {
        let (value, _) = try ConfigParser.parseQuoted(#""a\"b\\c\nd\te""#, lineNo: 1)
        XCTAssertEqual(value, "a\"b\\c\nd\te")
    }

    func testParseQuotedErrors() {
        XCTAssertThrowsError(try ConfigParser.parseQuoted("btw\"", lineNo: 3)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 3, message: "expected opening quote"))
        }
        XCTAssertThrowsError(try ConfigParser.parseQuoted("\"btw", lineNo: 4)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 4, message: "unterminated string"))
        }
        XCTAssertThrowsError(try ConfigParser.parseQuoted(#""a\q""#, lineNo: 5)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 5, message: "unknown escape '\\q'"))
        }
        XCTAssertThrowsError(try ConfigParser.parseQuoted(#""a\"#, lineNo: 6)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 6, message: "unterminated string"))
        }
    }

    // MARK: parseChord

    func testParseChordPlainKey() throws {
        XCTAssertEqual(try ConfigParser.parseChord("down", lineNo: 1),
                       Chord(keyCode: 0x7D, modifiers: []))
    }

    func testParseChordModifiersAndCase() throws {
        XCTAssertEqual(try ConfigParser.parseChord(" OPT + Shift + J ", lineNo: 1),
                       Chord(keyCode: 0x26, modifiers: [.opt, .shift]))
        XCTAssertEqual(try ConfigParser.parseChord("alt+j", lineNo: 1),
                       try ConfigParser.parseChord("opt+j", lineNo: 1))
    }

    func testParseChordErrors() {
        XCTAssertThrowsError(try ConfigParser.parseChord("opt+bogus", lineNo: 7)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 7, message: "unknown key 'bogus'"))
        }
        XCTAssertThrowsError(try ConfigParser.parseChord("meta+j", lineNo: 8)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 8, message: "unknown modifier 'meta'"))
        }
        XCTAssertThrowsError(try ConfigParser.parseChord("opt+opt+j", lineNo: 9)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 9, message: "duplicate modifier 'opt'"))
        }
        XCTAssertThrowsError(try ConfigParser.parseChord("opt++j", lineNo: 10)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 10, message: "empty name in chord 'opt++j'"))
        }
        XCTAssertThrowsError(try ConfigParser.parseChord("", lineNo: 11)) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 11, message: "empty name in chord ''"))
        }
    }

    // MARK: KeymapRule.output

    func testOutputMergesPassThroughModifiers() {
        let rule = KeymapRule(source: Chord(keyCode: 0x26, modifiers: [.opt]),
                              target: Chord(keyCode: 0x7D, modifiers: []),
                              line: 1)
        XCTAssertEqual(rule.output(pressed: [.opt]), Chord(keyCode: 0x7D, modifiers: []))
        XCTAssertEqual(rule.output(pressed: [.opt, .shift]),
                       Chord(keyCode: 0x7D, modifiers: [.shift]))
    }

    func testOutputAddsTargetModifiers() {
        let rule = KeymapRule(source: Chord(keyCode: 0x02, modifiers: [.opt]),
                              target: Chord(keyCode: 0x7C, modifiers: [.cmd]),
                              line: 1)
        XCTAssertEqual(rule.output(pressed: [.opt, .shift]),
                       Chord(keyCode: 0x7C, modifiers: [.cmd, .shift]))
    }
}
