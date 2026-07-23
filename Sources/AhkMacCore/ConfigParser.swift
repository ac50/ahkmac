public enum ConfigParser {
    /// Parses a whole config file. Rule shapes:
    ///   chord :: chord              key remap
    ///   "trigger" => "replacement"  hotstring, fires on an end char
    ///   *"trigger" => "replacement" hotstring, fires immediately
    public static func parse(_ text: String) throws -> Config {
        var keymaps: [KeymapRule] = []
        var hotstrings: [HotstringRule] = []
        var keymapLines: [Chord: Int] = [:]
        var triggerLines: [String: Int] = [:]

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let lineNo = index + 1
            let line = trim(stripComment(rawLine))
            if line.isEmpty { continue }

            if line.first == "\"" || line.first == "*" {
                let rule = try parseHotstring(line, lineNo: lineNo)
                if let first = triggerLines[rule.trigger] {
                    throw ConfigError(line: lineNo,
                        message: "duplicate trigger \"\(rule.trigger)\" (first defined on line \(first))")
                }
                triggerLines[rule.trigger] = lineNo
                hotstrings.append(rule)
            } else if line.contains("::") {
                let rule = try parseKeymap(line, lineNo: lineNo)
                if let first = keymapLines[rule.source] {
                    throw ConfigError(line: lineNo,
                        message: "duplicate keymap source (first defined on line \(first))")
                }
                keymapLines[rule.source] = lineNo
                keymaps.append(rule)
            } else {
                throw ConfigError(line: lineNo,
                    message: "unrecognized rule; expected 'chord :: chord' or '\"trigger\" => \"replacement\"'")
            }
        }
        return Config(keymaps: keymaps, hotstrings: hotstrings)
    }

    static func parseKeymap(_ line: Substring, lineNo: Int) throws -> KeymapRule {
        guard let separator = line.firstRange(of: "::"),
              line[separator.upperBound...].firstRange(of: "::") == nil else {
            throw ConfigError(line: lineNo, message: "expected exactly one '::'")
        }
        let source = try parseChord(line[..<separator.lowerBound], lineNo: lineNo)
        let target = try parseChord(line[separator.upperBound...], lineNo: lineNo)
        return KeymapRule(source: source, target: target, line: lineNo)
    }

    static func parseHotstring(_ line: Substring, lineNo: Int) throws -> HotstringRule {
        var rest = line
        var immediate = false
        if rest.first == "*" {
            immediate = true
            rest = trimLeading(rest.dropFirst())
        }
        let (trigger, afterTrigger) = try parseQuoted(rest, lineNo: lineNo)
        if trigger.isEmpty {
            throw ConfigError(line: lineNo, message: "empty trigger")
        }
        if let bad = trigger.first(where: { HotstringRule.endChars.contains($0) }) {
            throw ConfigError(line: lineNo,
                message: "trigger must not contain end character '\(bad)'")
        }
        var rest2 = trimLeading(afterTrigger)
        guard rest2.hasPrefix("=>") else {
            throw ConfigError(line: lineNo, message: "expected '=>' after trigger")
        }
        rest2 = trimLeading(rest2.dropFirst(2))
        let (replacement, tail) = try parseQuoted(rest2, lineNo: lineNo)
        if !trim(tail).isEmpty {
            throw ConfigError(line: lineNo, message: "unexpected content after replacement")
        }
        return HotstringRule(trigger: trigger, replacement: replacement,
                             immediate: immediate, line: lineNo)
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

    /// Parses a double-quoted string starting at `input`'s first character.
    /// Supported escapes: \" \\ \n \t. Returns the decoded value and the
    /// remainder after the closing quote.
    static func parseQuoted(_ input: Substring, lineNo: Int) throws -> (value: String, rest: Substring) {
        var rest = input
        guard rest.first == "\"" else {
            throw ConfigError(line: lineNo, message: "expected opening quote")
        }
        rest = rest.dropFirst()
        var value = ""
        while let ch = rest.first {
            rest = rest.dropFirst()
            switch ch {
            case "\"":
                return (value, rest)
            case "\\":
                guard let escape = rest.first else {
                    throw ConfigError(line: lineNo, message: "unterminated string")
                }
                rest = rest.dropFirst()
                switch escape {
                case "\"": value.append("\"")
                case "\\": value.append("\\")
                case "n": value.append("\n")
                case "t": value.append("\t")
                default:
                    throw ConfigError(line: lineNo, message: "unknown escape '\\\(escape)'")
                }
            default:
                value.append(ch)
            }
        }
        throw ConfigError(line: lineNo, message: "unterminated string")
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
