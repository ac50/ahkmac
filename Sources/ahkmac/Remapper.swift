import AhkMacCore
import CoreGraphics
import Foundation

/// Marker set on every event ahkmac synthesizes so the tap callback can
/// pass them through untouched (prevents self-triggering loops).
let syntheticEventMarker: Int64 = 0x61686B6D // "ahkm"

func log(_ message: String) {
    fputs("ahkmac: \(message)\n", stderr)
}

final class Remapper {
    let configPath: String
    var eventTap: CFMachPort?
    private var resolver: KeymapResolver
    private var engine: HotstringEngine
    /// Physical key codes whose keyDown was rewritten; their keyUp gets the
    /// same rewrite even if the modifiers were already released.
    private var activeRewrites: [UInt16: Chord] = [:]
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let backspaceKeyCode = CGKeyCode(KeySymbols.keyNames["delete"]!)

    init(config: Config, configPath: String) {
        self.configPath = configPath
        self.resolver = KeymapResolver(rules: config.keymaps)
        self.engine = HotstringEngine(rules: config.hotstrings)
    }

    func reload() {
        do {
            let config = try loadConfig(atPath: configPath)
            resolver = KeymapResolver(rules: config.keymaps)
            engine = HotstringEngine(rules: config.hotstrings)
            activeRewrites.removeAll()
            log("reloaded \(configPath): \(config.keymaps.count) keymaps, \(config.hotstrings.count) hotstrings")
        } catch {
            log("reload failed, keeping current config: \(error)")
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDown, .rightMouseDown:
            engine.reset()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if let target = activeRewrites.removeValue(forKey: keyCode) {
                rewrite(event, to: target)
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let pressed = Modifiers(flags: event.flags)

        if let rule = resolver.resolve(keyCode: keyCode, pressed: pressed) {
            let target = rule.output(pressed: pressed)
            activeRewrites[keyCode] = target
            engine.reset()
            rewrite(event, to: target)
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
           let target = activeRewrites[keyCode] {
            // A modifier was released mid-hold; keep autorepeats consistent.
            rewrite(event, to: target)
            return Unmanaged.passUnretained(event)
        }
        activeRewrites.removeValue(forKey: keyCode)

        if pressed.contains(.cmd) || pressed.contains(.ctrl) {
            engine.reset()
            return Unmanaged.passUnretained(event)
        }
        if keyCode == UInt16(backspaceKeyCode) {
            if pressed.isEmpty || pressed == [.shift] {
                engine.handleBackspace()
            } else {
                engine.reset() // opt+delete removes a whole word; buffer can't track that
            }
            return Unmanaged.passUnretained(event)
        }
        guard let ch = typedCharacter(of: event) else {
            engine.reset()
            return Unmanaged.passUnretained(event)
        }
        guard let replacement = engine.handleCharacter(ch) else {
            return Unmanaged.passUnretained(event)
        }
        post(replacement, originalEvent: event)
        return nil // suppress the event that completed the trigger
    }

    private func typedCharacter(of event: CGEvent) -> Character? {
        var length = 0
        var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count,
                                       actualStringLength: &length,
                                       unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        guard text.count == 1 else { return nil }
        return text.first
    }

    private func rewrite(_ event: CGEvent, to target: Chord) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(target.keyCode))
        event.flags = target.modifiers.cgFlags
    }

    private func post(_ replacement: Replacement, originalEvent: CGEvent) {
        for _ in 0..<replacement.backspaces {
            postSynthetic(CGEvent(keyboardEventSource: eventSource,
                                  virtualKey: backspaceKeyCode, keyDown: true))
            postSynthetic(CGEvent(keyboardEventSource: eventSource,
                                  virtualKey: backspaceKeyCode, keyDown: false))
        }
        let units = Array(replacement.text.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + 20, units.count)
            // never split a surrogate pair across chunks
            if end < units.count && (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
            let chunk = Array(units[start..<end])
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            postSynthetic(down)
            postSynthetic(CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false))
            start = end
        }
        if replacement.repostTrigger {
            // Keep the original flags: the end char itself may need shift ('!').
            postMarked(originalEvent.copy())
        }
    }

    /// Synthesized backspaces/text must not inherit modifiers the user is
    /// still physically holding (e.g. shift while typing the '!' end char).
    private func postSynthetic(_ event: CGEvent?) {
        event?.flags = []
        postMarked(event)
    }

    private func postMarked(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }
}

extension Modifiers {
    init(flags: CGEventFlags) {
        self = []
        if flags.contains(.maskCommand) { insert(.cmd) }
        if flags.contains(.maskAlternate) { insert(.opt) }
        if flags.contains(.maskControl) { insert(.ctrl) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskSecondaryFn) { insert(.fn) }
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.cmd) { flags.insert(.maskCommand) }
        if contains(.opt) { flags.insert(.maskAlternate) }
        if contains(.ctrl) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.fn) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
