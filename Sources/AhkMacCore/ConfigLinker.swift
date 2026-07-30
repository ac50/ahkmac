/// The output of ConfigParser's pass 1: lines scanned into rules with
/// section state tracked, but set names / scopes / macro references not
/// yet resolved. Set declarations may appear anywhere in the file —
/// including after the sections that reference them — so resolution
/// happens as a second pass over the whole file (`ConfigLinker.link`).
struct RawConfig {
    var sets: [AppsDecl] = []
    var headers: [ScopeToken] = []
    var macros: [MacroDef] = []
    var keymaps: [RawKeymap] = []
    var hotstrings: [RawHotstring] = []
}

/// A parsed `apps <name> = <id>, <id>, ...` declaration. IDs are already
/// lowercased.
struct AppsDecl {
    let name: String
    let ids: [String]
    let line: Int
}

/// A section header's scope, before its name is resolved against the set
/// table (or recognized as a literal bundle ID). `.name`'s `line` is the
/// header's own line, used to report an unknown-set error even when the
/// section it introduces has no rules.
enum ScopeToken {
    case global
    case name(String, negated: Bool, line: Int)
}

struct RawKeymap {
    let source: Chord
    let target: RawTarget
    let scope: ScopeToken
    let line: Int
}

enum RawTarget {
    case chord(Chord)
    case macroName(String)
}

struct RawHotstring {
    let trigger: String
    let action: RawAction
    let immediate: Bool
    let scope: ScopeToken
    let line: Int
}

enum RawAction {
    case text(String)
    case macroName(String)
}

/// Pass 2: resolves set names and scopes, resolves macro references, and
/// replaces the old per-kind duplicate dictionaries with scope-overlap-aware
/// conflict detection (two rules only conflict if their scopes could both
/// match the same running app — see `Scope.mayOverlap`).
enum ConfigLinker {
    static func link(_ raw: RawConfig) throws -> Config {
        let sets = try buildSetTable(raw.sets)
        let macroIndex = try buildMacroTable(raw.macros)

        // Every section header is validated, even ones whose section
        // contains no rules — an unknown set name must still be reported.
        for header in raw.headers {
            _ = try resolveScope(header, sets: sets)
        }

        var keymaps: [KeymapRule] = []
        keymaps.reserveCapacity(raw.keymaps.count)
        for rawRule in raw.keymaps {
            let scope = try resolveScope(rawRule.scope, sets: sets)
            let target: KeymapTarget
            switch rawRule.target {
            case .chord(let chord):
                target = .chord(chord)
            case .macroName(let name):
                guard let index = macroIndex[name] else {
                    throw ConfigError(line: rawRule.line, message: "undefined macro '\(name)'")
                }
                target = .macro(index)
            }
            keymaps.append(KeymapRule(source: rawRule.source, target: target, scope: scope, line: rawRule.line))
        }

        var hotstrings: [HotstringRule] = []
        hotstrings.reserveCapacity(raw.hotstrings.count)
        for rawRule in raw.hotstrings {
            let scope = try resolveScope(rawRule.scope, sets: sets)
            let action: HotstringAction
            switch rawRule.action {
            case .text(let text):
                action = .text(text)
            case .macroName(let name):
                guard let index = macroIndex[name] else {
                    throw ConfigError(line: rawRule.line, message: "undefined macro '\(name)'")
                }
                action = .macro(index)
            }
            hotstrings.append(HotstringRule(trigger: rawRule.trigger, action: action,
                immediate: rawRule.immediate, scope: scope, line: rawRule.line))
        }

        try detectKeymapConflicts(keymaps)
        try detectHotstringConflicts(hotstrings)

        return Config(keymaps: keymaps, hotstrings: hotstrings, macros: raw.macros)
    }

    private static func buildSetTable(_ decls: [AppsDecl]) throws -> [String: AppsDecl] {
        var sets: [String: AppsDecl] = [:]
        for decl in decls {
            if let first = sets[decl.name] {
                throw ConfigError(line: decl.line,
                    message: "duplicate apps set '\(decl.name)' (first defined on line \(first.line))")
            }
            sets[decl.name] = decl
        }
        return sets
    }

    private static func buildMacroTable(_ macros: [MacroDef]) throws -> [String: Int] {
        var index: [String: Int] = [:]
        for (i, macro) in macros.enumerated() {
            if let first = index[macro.name] {
                throw ConfigError(line: macro.line,
                    message: "duplicate macro '\(macro.name)' (first defined on line \(macros[first].line))")
            }
            index[macro.name] = i
        }
        return index
    }

    /// Resolves a section header's scope token: `*` is global; a name
    /// containing '.' is a literal (lowercased) bundle ID; otherwise the
    /// name is looked up in the set table.
    private static func resolveScope(_ token: ScopeToken, sets: [String: AppsDecl]) throws -> Scope {
        switch token {
        case .global:
            return .global
        case .name(let name, let negated, let line):
            let ids: [String]
            if name.contains(".") {
                ids = [name.lowercased()]
            } else if let decl = sets[name] {
                ids = decl.ids
            } else {
                throw ConfigError(line: line,
                    message: "unknown apps set '\(name)' (bundle IDs contain a '.')")
            }
            return negated ? .exceptApps(ids) : .apps(ids)
        }
    }

    /// Groups rules by `source`, and within each group — sorted by line —
    /// flags the first pair whose scopes may overlap.
    private static func detectKeymapConflicts(_ rules: [KeymapRule]) throws {
        var groups: [Chord: [KeymapRule]] = [:]
        for rule in rules {
            groups[rule.source, default: []].append(rule)
        }
        for group in groups.values {
            let sorted = group.sorted { $0.line < $1.line }
            for i in 1..<sorted.count {
                for j in 0..<i where sorted[j].scope.mayOverlap(sorted[i].scope) {
                    throw ConfigError(line: sorted[i].line,
                        message: "duplicate keymap source (first defined on line \(sorted[j].line))")
                }
            }
        }
    }

    /// Groups rules by `trigger`, and within each group — sorted by line —
    /// flags the first pair whose scopes may overlap.
    private static func detectHotstringConflicts(_ rules: [HotstringRule]) throws {
        var groups: [String: [HotstringRule]] = [:]
        for rule in rules {
            groups[rule.trigger, default: []].append(rule)
        }
        for group in groups.values {
            let sorted = group.sorted { $0.line < $1.line }
            for i in 1..<sorted.count {
                for j in 0..<i where sorted[j].scope.mayOverlap(sorted[i].scope) {
                    throw ConfigError(line: sorted[i].line,
                        message: "duplicate trigger \"\(sorted[i].trigger)\" (first defined on line \(sorted[j].line))")
                }
            }
        }
    }
}
