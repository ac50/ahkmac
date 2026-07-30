public enum ConfigParser {
    /// Parses a whole config file. Rule shapes:
    ///   chord :: chord              key remap
    ///   "trigger" => "replacement"  hotstring, fires on an end char
    ///   *"trigger" => "replacement" hotstring, fires immediately
    /// Plus section/set declarations that scope the rules beneath them:
    ///   apps <name> = <bundle.id>, <bundle.id>, ...   named app set
    ///   [<bundle.id> | <set name> | !<set name> | *]  section header
    /// Parsing is a two-pass process: this pass scans lines into a
    /// `RawConfig` with section state tracked but not yet resolved;
    /// `ConfigLinker.link` resolves set names and scopes and detects
    /// scope-overlap-aware duplicates.
    public static func parse(_ text: String) throws -> Config {
        var raw = RawConfig()
        var scope = ScopeToken.global
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let lineNo = index + 1
            let line = trim(stripComment(rawLine))
            if line.isEmpty { continue }
            if line.first == "[" {
                scope = try parseSectionHeader(line, lineNo: lineNo)
                raw.headers.append(scope)                       // 空区块的错名也要能报出来
            } else if isKeyword(line, "apps") {
                raw.sets.append(try parseAppsDecl(line, lineNo: lineNo))
            } else if line.first == "\"" || line.first == "*" {
                raw.hotstrings.append(try parseHotstring(line, lineNo: lineNo, scope: scope))
            } else if line.contains("::") {
                raw.keymaps.append(try parseKeymap(line, lineNo: lineNo, scope: scope))
            } else {
                throw ConfigError(line: lineNo,
                    message: "unrecognized rule; expected 'chord :: chord' or '\"trigger\" => \"replacement\"'")
            }
        }
        return try ConfigLinker.link(raw)
    }

    static func parseKeymap(_ line: Substring, lineNo: Int, scope: ScopeToken) throws -> RawKeymap {
        guard let separator = line.firstRange(of: "::"),
              line[separator.upperBound...].firstRange(of: "::") == nil else {
            throw ConfigError(line: lineNo, message: "expected exactly one '::'")
        }
        let source = try parseChord(line[..<separator.lowerBound], lineNo: lineNo)
        let target = try parseChord(line[separator.upperBound...], lineNo: lineNo)
        return RawKeymap(source: source, target: .chord(target), scope: scope, line: lineNo)
    }

    static func parseHotstring(_ line: Substring, lineNo: Int, scope: ScopeToken) throws -> RawHotstring {
        var rest = line
        var immediate = false
        if rest.first == "*" {
            immediate = true
            rest = trimLeading(rest.dropFirst())
        }
        let (triggerChars, afterTrigger) = try parseQuotedMarked(rest, lineNo: lineNo)
        if triggerChars.isEmpty {
            throw ConfigError(line: lineNo, message: "empty trigger")
        }
        for qc in triggerChars {
            if HotstringRule.whitespaceEndChars.contains(qc.value) {
                throw ConfigError(line: lineNo, message: "trigger must not contain whitespace")
            }
            if !qc.escaped && HotstringRule.punctuationEndChars.contains(qc.value) {
                throw ConfigError(line: lineNo,
                    message: "unescaped end character '\(qc.value)' in trigger (write '\\\(qc.value)')")
            }
        }
        let trigger = String(triggerChars.map(\.value))
        var rest2 = trimLeading(afterTrigger)
        guard rest2.hasPrefix("=>") else {
            throw ConfigError(line: lineNo, message: "expected '=>' after trigger")
        }
        rest2 = trimLeading(rest2.dropFirst(2))
        let (replacement, tail) = try parseQuoted(rest2, lineNo: lineNo)
        if !trim(tail).isEmpty {
            throw ConfigError(line: lineNo, message: "unexpected content after replacement")
        }
        return RawHotstring(trigger: trigger, action: .text(replacement),
                             immediate: immediate, scope: scope, line: lineNo)
    }

    /// Parses a `[...]` section header. Content is trimmed after removing
    /// the brackets; `*` means global, a leading `!` negates, empty or
    /// whitespace-containing names are rejected. The name itself (bundle
    /// ID vs. set name) is resolved later by ConfigLinker.
    static func parseSectionHeader(_ line: Substring, lineNo: Int) throws -> ScopeToken {
        guard line.last == "]" else {
            throw ConfigError(line: lineNo, message: "expected closing ']'")
        }
        let inner = trim(line.dropFirst().dropLast())
        if inner == "*" {
            return .global
        }
        var negated = false
        var name = inner
        if name.first == "!" {
            negated = true
            name = name.dropFirst()
        }
        if name.isEmpty {
            throw ConfigError(line: lineNo, message: "empty section name")
        }
        if name.contains(where: { $0 == " " || $0 == "\t" }) {
            throw ConfigError(line: lineNo, message: "section name must not contain whitespace")
        }
        return .name(String(name), negated: negated, line: lineNo)
    }

    /// Parses `apps <name> = <id>, <id>, ...`. IDs are trimmed and
    /// lowercased; the set name is validated by `validName`.
    static func parseAppsDecl(_ line: Substring, lineNo: Int) throws -> AppsDecl {
        let rest = trimLeading(line.dropFirst("apps".count))
        guard let eqIndex = rest.firstIndex(of: "=") else {
            throw ConfigError(line: lineNo, message: "expected '=' in apps declaration")
        }
        let name = String(trim(rest[..<eqIndex]))
        guard validName(name) else {
            throw ConfigError(line: lineNo,
                message: "invalid set name '\(name)' (letters, digits, '-', '_' only)")
        }
        let idsPart = trim(rest[rest.index(after: eqIndex)...])
        if idsPart.isEmpty {
            throw ConfigError(line: lineNo, message: "empty apps list for set '\(name)'")
        }
        var ids: [String] = []
        for piece in idsPart.split(separator: ",", omittingEmptySubsequences: false) {
            let id = trim(piece)
            if id.isEmpty {
                throw ConfigError(line: lineNo, message: "empty app id in apps list for set '\(name)'")
            }
            if id.contains(where: { $0 == " " || $0 == "\t" }) {
                throw ConfigError(line: lineNo, message: "app id must not contain whitespace")
            }
            ids.append(id.lowercased())
        }
        return AppsDecl(name: name, ids: ids, line: lineNo)
    }

    /// Set/macro names: letters, digits, '-', '_' only, non-empty.
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Whether `line` starts with the whole word `word` (i.e. `word`
    /// followed by a space or tab, not e.g. as a prefix of a longer token).
    static func isKeyword(_ line: Substring, _ word: String) -> Bool {
        guard line.hasPrefix(word) else { return false }
        let afterWord = line.index(line.startIndex, offsetBy: word.count)
        guard afterWord < line.endIndex else { return false }
        let next = line[afterWord]
        return next == " " || next == "\t"
    }

    /// Cuts the line at the first '#' that is not inside a quoted string.
    static func stripComment(_ line: Substring) -> Substring {
        var inQuotes = false
        var escaped = false
        for index in line.indices {
            let ch = line[index]
            if escaped { escaped = false; continue }
            if inQuotes && ch == "\\" { escaped = true; continue }
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == "#" && !inQuotes { return line[..<index] }
        }
        return line
    }

    static func trim(_ text: Substring) -> Substring {
        var text = text
        while let first = text.first, first == " " || first == "\t" || first == "\r" {
            text = text.dropFirst()
        }
        while let last = text.last, last == " " || last == "\t" || last == "\r" {
            text = text.dropLast()
        }
        return text
    }

    static func trimLeading(_ text: Substring) -> Substring {
        var text = text
        while let first = text.first, first == " " || first == "\t" {
            text = text.dropFirst()
        }
        return text
    }

    /// One decoded character plus whether it was written as an escape —
    /// escaped punctuation end chars are allowed inside triggers.
    struct QuotedChar {
        let value: Character
        let escaped: Bool
    }

    /// Parses a double-quoted string starting at `input`'s first character.
    /// Escapes: \" \\ \n \t plus every punctuation end char (\- \. \! …),
    /// which decodes to itself. Returns the remainder after the closing quote.
    static func parseQuotedMarked(_ input: Substring, lineNo: Int) throws -> (chars: [QuotedChar], rest: Substring) {
        var rest = input
        guard rest.first == "\"" else {
            throw ConfigError(line: lineNo, message: "expected opening quote")
        }
        rest = rest.dropFirst()
        var chars: [QuotedChar] = []
        while let ch = rest.first {
            rest = rest.dropFirst()
            switch ch {
            case "\"":
                return (chars, rest)
            case "\\":
                guard let escape = rest.first else {
                    throw ConfigError(line: lineNo, message: "unterminated string")
                }
                rest = rest.dropFirst()
                switch escape {
                case "n": chars.append(QuotedChar(value: "\n", escaped: true))
                case "t": chars.append(QuotedChar(value: "\t", escaped: true))
                default:
                    // \" and \\ are members of punctuationEndChars too.
                    guard HotstringRule.punctuationEndChars.contains(escape) else {
                        throw ConfigError(line: lineNo, message: "unknown escape '\\\(escape)'")
                    }
                    chars.append(QuotedChar(value: escape, escaped: true))
                }
            default:
                chars.append(QuotedChar(value: ch, escaped: false))
            }
        }
        throw ConfigError(line: lineNo, message: "unterminated string")
    }

    static func parseQuoted(_ input: Substring, lineNo: Int) throws -> (value: String, rest: Substring) {
        let (chars, rest) = try parseQuotedMarked(input, lineNo: lineNo)
        return (String(chars.map(\.value)), rest)
    }

    /// Parses "mod+mod+key" (any number of modifiers, case-insensitive).
    static func parseChord(_ text: Substring, lineNo: Int) throws -> Chord {
        let tokens = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { String(trim($0)).lowercased() }
        for token in tokens where token.isEmpty {
            throw ConfigError(line: lineNo, message: "empty name in chord '\(trim(text))'")
        }
        var modifiers: Modifiers = []
        for token in tokens.dropLast() {
            guard let modifier = KeySymbols.modifierNames[token] else {
                throw ConfigError(line: lineNo, message: "unknown modifier '\(token)'")
            }
            if modifiers.contains(modifier) {
                throw ConfigError(line: lineNo, message: "duplicate modifier '\(token)'")
            }
            modifiers.insert(modifier)
        }
        guard let keyToken = tokens.last, let keyCode = KeySymbols.keyNames[keyToken] else {
            throw ConfigError(line: lineNo, message: "unknown key '\(tokens.last ?? "")'")
        }
        return Chord(keyCode: keyCode, modifiers: modifiers)
    }
}
