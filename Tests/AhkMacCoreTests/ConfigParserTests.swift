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
                       target: .chord(Chord(keyCode: 0x7D, modifiers: [])), scope: .global, line: 2),
            KeymapRule(source: Chord(keyCode: 0x28, modifiers: [.opt]),
                       target: .chord(Chord(keyCode: 0x7E, modifiers: [])), scope: .global, line: 3),
            KeymapRule(source: Chord(keyCode: 0x02, modifiers: [.opt]),
                       target: .chord(Chord(keyCode: 0x7C, modifiers: [.cmd])), scope: .global, line: 5),
        ])
        XCTAssertEqual(config.hotstrings, [
            HotstringRule(trigger: "btw", action: .text("by the way"), immediate: false, scope: .global, line: 6),
            HotstringRule(trigger: "@@", action: .text("user@example.com"), immediate: true, scope: .global, line: 7),
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
                       HotstringRule(trigger: "btw.", action: .text("by the way."),
                                     immediate: true, scope: .global, line: 1))
    }

    func testStarWithoutQuoteRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("*btw => \"y\"")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "expected opening quote"))
        }
    }

    func testReplacementMayContainAnything() throws {
        let config = try ConfigParser.parse(#""sig" => "Bye!\n-- yt :: #1""#)
        XCTAssertEqual(config.hotstrings.first?.action, .text("Bye!\n-- yt :: #1"))
    }

    // MARK: sections, sets, scoped conflict detection

    func testScopedRules() throws {
        let config = try ConfigParser.parse("""
        apps editors = com.microsoft.VSCode, com.apple.dt.Xcode
        [com.google.Chrome]
        opt+j :: down
        "gm" => "gmail.com"
        [editors]
        opt+b :: cmd+left
        [!editors]
        opt+e :: cmd+right
        [*]
        opt+k :: up
        """)
        let editors = ["com.microsoft.vscode", "com.apple.dt.xcode"]
        XCTAssertEqual(config.keymaps.map(\.scope),
                       [.apps(["com.google.chrome"]), .apps(editors), .exceptApps(editors), .global])
        XCTAssertEqual(config.hotstrings.map(\.scope), [.apps(["com.google.chrome"])])
    }

    func testSetDeclaredAfterUseIsFine() throws {
        let config = try ConfigParser.parse("[eds]\nopt+j :: down\n[*]\napps eds = com.a.b\n")
        XCTAssertEqual(config.keymaps.first?.scope, .apps(["com.a.b"]))
    }

    func testUnknownSetRejectedEvenInEmptySection() {
        XCTAssertThrowsError(try ConfigParser.parse("[nope]\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 1, message: "unknown apps set 'nope' (bundle IDs contain a '.')"))
        }
    }

    func testScopeConflictMatrix() throws {
        // 同区块重复 → 报错(沿用旧文案)
        XCTAssertThrowsError(try ConfigParser.parse("[com.a.b]\nopt+j :: down\nopt+j :: up\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 3, message: "duplicate keymap source (first defined on line 2)"))
        }
        // 两个正向区块有交集 → 报错
        XCTAssertThrowsError(try ConfigParser.parse("""
        apps s1 = com.a.b, com.c.d
        apps s2 = com.c.d
        [s1]
        opt+j :: down
        [s2]
        opt+j :: up
        """))
        // 两个反向区块必然重叠 → 报错
        XCTAssertThrowsError(try ConfigParser.parse("[!com.a.b]\nopt+j :: down\n[!com.c.d]\nopt+j :: up\n"))
        // 不同层级 → 合法;正向不相交 → 合法
        XCTAssertEqual(try ConfigParser.parse("opt+j :: down\n[com.a.b]\nopt+j :: up\n").keymaps.count, 2)
        XCTAssertEqual(try ConfigParser.parse("[com.a.b]\nopt+j :: down\n[com.c.d]\nopt+j :: up\n").keymaps.count, 2)
    }

    func testDuplicateSetRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("apps s = com.a.b\napps s = com.c.d\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 2, message: "duplicate apps set 's' (first defined on line 1)"))
        }
    }

    func testInvalidSetName() {
        XCTAssertThrowsError(try ConfigParser.parse("apps a.b = x.y\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 1, message: "invalid set name 'a.b' (letters, digits, '-', '_' only)"))
        }
    }

    func testEmptyAppList() {
        XCTAssertThrowsError(try ConfigParser.parse("apps s =\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 1, message: "empty apps list for set 's'"))
        }
    }

    func testSetEntryWithoutDotRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("apps work = editors\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 1,
                    message: "bad bundle ID 'editors' in apps declaration (bundle IDs contain a '.')"))
        }
    }

    func testBadSectionHeaders() {
        XCTAssertThrowsError(try ConfigParser.parse("[]\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "empty section name"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("[!]\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "empty section name"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("[a b]\n")) {
            XCTAssertEqual($0 as? ConfigError,
                           ConfigError(line: 1, message: "section name must not contain whitespace or ','"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("[x\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "expected closing ']'"))
        }
    }

    func testCommaInSectionHeaderRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("[com.a,com.b]\nopt+j :: down\n")) {
            XCTAssertEqual($0 as? ConfigError,
                           ConfigError(line: 1, message: "section name must not contain whitespace or ','"))
        }
    }

    func testScopedTriggerConflict() throws {
        XCTAssertThrowsError(try ConfigParser.parse("[com.a.b]\n\"x\" => \"a\"\n\"x\" => \"b\"\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 3, message: "duplicate trigger \"x\" (first defined on line 2)"))
        }
        let config = try ConfigParser.parse("\"x\" => \"a\"\n[com.a.b]\n\"x\" => \"b\"\n")
        XCTAssertEqual(config.hotstrings.count, 2)
    }

    func testBundleIDCaseInsensitive() throws {
        let config = try ConfigParser.parse("[COM.Google.Chrome]\nopt+j :: down\n")
        XCTAssertEqual(config.keymaps.first?.scope, .apps(["com.google.chrome"]))
    }

    // MARK: macros

    func testMacroDefinitionAndBindings() throws {
        let config = try ConfigParser.parse("""
        opt+y :: macro copy-line          # 先绑定后定义,合法
        *"@sig" => macro copy-line
        macro copy-line {
            key cmd+shift+right
            sleep 100
            text "done\\n"
            run "open -a Notes"
        }
        """)
        XCTAssertEqual(config.macros, [MacroDef(name: "copy-line", steps: [
            .key(Chord(keyCode: 0x7C, modifiers: [.cmd, .shift])),
            .sleep(100),
            .text("done\n"),
            .run("open -a Notes"),
        ], line: 3)])
        XCTAssertEqual(config.keymaps.first?.target, .macro(0))
        XCTAssertEqual(config.hotstrings.first?.action, .macro(0))
    }

    func testMacroInsideSectionIsGlobalAndScopeStillApplies() throws {
        let config = try ConfigParser.parse("""
        [com.a.b]
        opt+y :: macro m
        macro m {
            key cmd+c
        }
        """)
        XCTAssertEqual(config.macros.count, 1)                       // 定义不受区块影响
        XCTAssertEqual(config.keymaps.first?.scope, .apps(["com.a.b"]))  // 绑定受区块约束
    }

    func testEmptyMacroRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n}\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "empty macro 'm'"))
        }
    }

    func testDuplicateMacroRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("""
        macro m {
            key cmd+c
        }
        macro m {
            key cmd+d
        }
        """)) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 4, message: "duplicate macro 'm' (first defined on line 1)"))
        }
    }

    func testUndefinedMacroRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("opt+y :: macro nope\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "undefined macro 'nope'"))
        }
    }

    func testUnclosedMacroRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n    key cmd+c\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 1, message: "unclosed macro block 'm'"))
        }
    }

    func testBadActionRejected() {
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n    beep 3\n}\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 2, message: "unknown macro action 'beep' (key/text/sleep/run)"))
        }
    }

    func testSleepRange() {
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n    sleep -1\n}\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 2, message: "sleep out of range 0-10000"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n    sleep 10001\n}\n")) {
            XCTAssertEqual($0 as? ConfigError, ConfigError(line: 2, message: "sleep out of range 0-10000"))
        }
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n    sleep x\n}\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 2, message: "sleep wants an integer millisecond count"))
        }
    }

    func testMacroHeaderNeedsBrace() {
        XCTAssertThrowsError(try ConfigParser.parse("macro m\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 1, message: "expected '{' at end of macro header"))
        }
    }

    func testJunkAfterCloseBrace() {
        XCTAssertThrowsError(try ConfigParser.parse("macro m {\n    key cmd+c\n} x\n")) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 3)
        }
    }

    func testMacroNameValidated() {
        XCTAssertThrowsError(try ConfigParser.parse("macro a.b {\n")) {
            XCTAssertEqual($0 as? ConfigError,
                ConfigError(line: 1, message: "invalid macro name 'a.b' (letters, digits, '-', '_' only)"))
        }
    }
}
