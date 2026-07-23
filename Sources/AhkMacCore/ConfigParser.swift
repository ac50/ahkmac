public enum ConfigParser {
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
