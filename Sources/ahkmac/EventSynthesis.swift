import AhkMacCore
import CoreGraphics
import Foundation

/// Event synthesis shared by hotstring replacement and macro execution.
enum EventSynthesis {
    static let backspaceKeyCode = CGKeyCode(KeySymbols.keyNames["delete"]!)

    /// Marks and posts; synthesized events must not inherit physically
    /// held modifiers, so callers set flags explicitly beforehand.
    static func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    static func postBackspaces(_ count: Int, source: CGEventSource?) {
        for _ in 0..<count {
            postClean(CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: true))
            postClean(CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: false))
        }
    }

    static func postText(_ text: String, source: CGEventSource?) {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + 20, units.count)
            if end < units.count && (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
            let chunk = Array(units[start..<end])
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            postClean(down)
            postClean(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false))
            start = end
        }
    }

    /// One full press of a chord, with exactly the chord's modifiers.
    static func postChord(_ chord: Chord, source: CGEventSource?) {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source,
                                virtualKey: CGKeyCode(chord.keyCode), keyDown: keyDown)
            event?.flags = chord.modifiers.cgFlags
            post(event)
        }
    }

    private static func postClean(_ event: CGEvent?) {
        event?.flags = []
        post(event)
    }
}
