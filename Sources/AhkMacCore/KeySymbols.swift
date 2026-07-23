/// Domain model kept free of CoreGraphics types so the core library
/// stays platform-independent and fully unit-testable.
public struct Modifiers: OptionSet, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let cmd = Modifiers(rawValue: 1 << 0)
    public static let opt = Modifiers(rawValue: 1 << 1)
    public static let ctrl = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let fn = Modifiers(rawValue: 1 << 4)

    public var count: Int { rawValue.nonzeroBitCount }
}

public struct Chord: Hashable {
    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Names accepted in config files, mapped to ANSI-layout virtual key
/// codes (Carbon kVK_* values) and modifier flags. Lookup is done on
/// lowercased tokens, so names here must be lowercase.
public enum KeySymbols {
    public static let modifierNames: [String: Modifiers] = [
        "cmd": .cmd, "opt": .opt, "alt": .opt,
        "ctrl": .ctrl, "shift": .shift, "fn": .fn,
    ]

    public static let keyNames: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "equal": 0x18, "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C,
        "0": 0x1D, "rightbracket": 0x1E, "o": 0x1F, "u": 0x20,
        "leftbracket": 0x21, "i": 0x22, "p": 0x23, "enter": 0x24,
        "return": 0x24, "l": 0x25, "j": 0x26, "quote": 0x27, "k": 0x28,
        "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B, "slash": 0x2C,
        "n": 0x2D, "m": 0x2E, "period": 0x2F, "tab": 0x30, "space": 0x31,
        "grave": 0x32, "delete": 0x33, "esc": 0x35,
        "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f3": 0x63, "f8": 0x64,
        "f9": 0x65, "f11": 0x67, "f13": 0x69, "f16": 0x6A, "f14": 0x6B,
        "f10": 0x6D, "f12": 0x6F, "f15": 0x71,
        "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "f4": 0x76,
        "end": 0x77, "f2": 0x78, "pagedown": 0x79, "f1": 0x7A,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}
