/// What a keymap rule emits when it fires: a chord to synthesize, or a
/// macro to run (index into `Config.macros`).
public enum KeymapTarget: Hashable {
    case chord(Chord)
    case macro(Int)
}

/// What a hotstring fires: literal replacement text, or a macro to run
/// (index into `Config.macros`).
public enum HotstringAction: Hashable {
    case text(String)
    case macro(Int)
}

/// One step of a macro's script.
public enum MacroStep: Hashable {
    case key(Chord)
    case text(String)
    case sleep(Int)
    case run(String)
}

/// A named, reusable sequence of steps that a keymap or hotstring can
/// target by index into `Config.macros`.
public struct MacroDef: Hashable {
    public let name: String
    public let steps: [MacroStep]
    public let line: Int

    public init(name: String, steps: [MacroStep], line: Int) {
        self.name = name
        self.steps = steps
        self.line = line
    }
}

public struct KeymapRule: Hashable {
    public let source: Chord
    public let target: KeymapTarget
    public let scope: Scope
    public let line: Int

    public init(source: Chord, target: KeymapTarget, scope: Scope, line: Int) {
        self.source = source
        self.target = target
        self.scope = scope
        self.line = line
    }

    /// The chord to emit when this rule fires: the target's modifiers plus
    /// any pressed modifiers the source did not consume (pass-through, so
    /// e.g. `opt+j :: down` pressed with shift yields shift+down). nil when
    /// the target is a macro — there is no chord to emit.
    public func chordOutput(pressed: Modifiers) -> Chord? {
        guard case .chord(let target) = target else { return nil }
        return Chord(keyCode: target.keyCode,
                     modifiers: target.modifiers.union(pressed.subtracting(source.modifiers)))
    }
}

public struct HotstringRule: Hashable {
    public let trigger: String
    public let action: HotstringAction
    public let immediate: Bool
    public let scope: Scope
    public let line: Int

    public init(trigger: String, action: HotstringAction, immediate: Bool, scope: Scope, line: Int) {
        self.trigger = trigger
        self.action = action
        self.immediate = immediate
        self.scope = scope
        self.line = line
    }

    /// Characters that end a word and fire end-char-mode hotstrings.
    /// Punctuation end chars may appear inside a trigger when escaped
    /// (e.g. "e\-mail"); whitespace never may.
    public static let punctuationEndChars: Set<Character> = [
        "-", "(", ")", "[", "]", "{", "}",
        "'", ":", ";", "\"", "/", "\\", ",", ".", "?", "!",
    ]
    public static let whitespaceEndChars: Set<Character> = [" ", "\t", "\r", "\n"]
    public static let endChars = punctuationEndChars.union(whitespaceEndChars)
}

public struct Config: Equatable {
    public let keymaps: [KeymapRule]
    public let hotstrings: [HotstringRule]
    public let macros: [MacroDef]

    public init(keymaps: [KeymapRule], hotstrings: [HotstringRule], macros: [MacroDef] = []) {
        self.keymaps = keymaps
        self.hotstrings = hotstrings
        self.macros = macros
    }
}

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String { "line \(line): \(message)" }
}

/// Where a rule applies: everywhere, only in the listed apps, or
/// everywhere except them. Bundle IDs are stored lowercased; callers
/// must lowercase the active app before matching.
public enum Scope: Hashable {
    case global
    case apps([String])
    case exceptApps([String])

    /// Precedence tier: positive scope beats negated beats global.
    public var level: Int {
        switch self {
        case .apps: return 2
        case .exceptApps: return 1
        case .global: return 0
        }
    }

    public func matches(app: String?) -> Bool {
        switch self {
        case .global:
            return true
        case .apps(let ids):
            guard let app else { return false }
            return ids.contains(app)
        case .exceptApps(let ids):
            guard let app else { return true }
            return !ids.contains(app)
        }
    }

    /// Whether two scopes of the same tier could both match some app —
    /// the static ambiguity check behind duplicate detection. Different
    /// tiers never count: the more specific rule wins at runtime.
    public func mayOverlap(_ other: Scope) -> Bool {
        switch (self, other) {
        case (.global, .global), (.exceptApps, .exceptApps):
            return true
        case (.apps(let a), .apps(let b)):
            return !Set(a).isDisjoint(with: b)
        default:
            return false
        }
    }
}
