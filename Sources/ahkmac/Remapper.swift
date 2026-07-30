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
    private let frontmostBundleID: () -> String?
    private var macros: [MacroDef]
    private let macroRunner: MacroRunner
    private var macroHeldKeys: Set<UInt16> = []

    init(config: Config, configPath: String, frontmostBundleID: @escaping () -> String?) {
        self.configPath = configPath
        self.resolver = KeymapResolver(rules: config.keymaps)
        self.engine = HotstringEngine(rules: config.hotstrings)
        self.frontmostBundleID = frontmostBundleID
        self.macros = config.macros
        self.macroRunner = MacroRunner(source: eventSource)
    }

    func reload() {
        do {
            let config = try loadConfig(atPath: configPath)
            resolver = KeymapResolver(rules: config.keymaps)
            engine = HotstringEngine(rules: config.hotstrings)
            macros = config.macros
            activeRewrites.removeAll()
            log("reloaded \(configPath): \(config.keymaps.count) keymaps, \(config.hotstrings.count) hotstrings, \(config.macros.count) macros")
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
            if macroHeldKeys.remove(keyCode) != nil {
                activeRewrites.removeValue(forKey: keyCode)   // clear a stale chord rewrite for this keyCode
                return nil                                    // 宏绑定键的抬起也吞掉
            }
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
        let app = frontmostBundleID()
        engine.setActiveApp(app)

        if let rule = resolver.resolve(keyCode: keyCode, pressed: pressed, app: app) {
            engine.reset()
            switch rule.target {
            case .chord:
                let target = rule.chordOutput(pressed: pressed)!
                activeRewrites[keyCode] = target
                rewrite(event, to: target)
                return Unmanaged.passUnretained(event)
            case .macro(let index):
                engine.reset()
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return nil                    // 长按自动重复:吞掉但不重放宏
                }
                macroHeldKeys.insert(keyCode)
                macroRunner.run(macros[index])
                return nil
            }
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
        if keyCode == UInt16(EventSynthesis.backspaceKeyCode) {
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
        guard let firing = engine.handleCharacter(ch) else {
            return Unmanaged.passUnretained(event)
        }
        post(firing, originalEvent: event)
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

    private func post(_ firing: Firing, originalEvent: CGEvent) {
        EventSynthesis.postBackspaces(firing.backspaces, source: eventSource)
        switch firing.output {
        case .text(let text, let repost):
            EventSynthesis.postText(text, source: eventSource)
            if repost { EventSynthesis.post(originalEvent.copy()) }  // 结束符重放,保留原 flags
        case .macro(let index):
            macroRunner.run(macros[index])                           // 结束符已吞掉,不重放
        }
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
