/// What to do when a hotstring fires. The caller must suppress the event
/// that produced the decisive character, synthesize `backspaces` backspace
/// presses, type `text`, and, if `repostTrigger` is set (end-char mode),
/// re-post a copy of the suppressed original event afterwards.
public struct Replacement: Equatable {
    public let backspaces: Int
    public let text: String
    public let repostTrigger: Bool

    public init(backspaces: Int, text: String, repostTrigger: Bool) {
        self.backspaces = backspaces
        self.text = text
        self.repostTrigger = repostTrigger
    }
}

/// Tracks recently typed characters and decides when a hotstring fires.
/// Matching is by suffix (a trigger also fires mid-word, like AHK's `?`
/// option); the longest matching trigger wins.
public final class HotstringEngine {
    private let rules: [HotstringRule]
    private let maxTriggerLength: Int
    private var buffer: [Character] = []

    public init(rules: [HotstringRule]) {
        self.rules = rules
        self.maxTriggerLength = rules.map { $0.trigger.count }.max() ?? 0
    }

    /// Feed one typed character; nil means "let the event through".
    public func handleCharacter(_ ch: Character) -> Replacement? {
        if HotstringRule.endChars.contains(ch) {
            defer { buffer.removeAll() }
            if let rule = longestMatch(immediate: false) {
                return Replacement(backspaces: rule.trigger.count,
                                   text: rule.replacement, repostTrigger: true)
            }
            return nil
        }
        guard Self.isTypable(ch) else {
            buffer.removeAll()
            return nil
        }
        buffer.append(ch)
        if buffer.count > maxTriggerLength {
            buffer.removeFirst(buffer.count - maxTriggerLength)
        }
        if let rule = longestMatch(immediate: true) {
            buffer.removeAll()
            return Replacement(backspaces: rule.trigger.count - 1,
                               text: rule.replacement, repostTrigger: false)
        }
        return nil
    }

    public func handleBackspace() {
        if !buffer.isEmpty { buffer.removeLast() }
    }

    public func reset() {
        buffer.removeAll()
    }

    private func longestMatch(immediate: Bool) -> HotstringRule? {
        var best: HotstringRule?
        for rule in rules where rule.immediate == immediate
            && rule.trigger.count <= buffer.count
            && buffer.suffix(rule.trigger.count).elementsEqual(rule.trigger) {
            if best == nil || rule.trigger.count > best!.trigger.count {
                best = rule
            }
        }
        return best
    }

    /// Printable text goes in the buffer. Control characters and the
    /// private-use characters macOS assigns to function/arrow keys clear
    /// it instead (the cursor context is no longer a plain word).
    static func isTypable(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let scalar = ch.unicodeScalars.first else {
            return true // multi-scalar grapheme (emoji etc.) is regular text
        }
        if scalar.value < 0x20 || scalar.value == 0x7F { return false }
        if (0xE000...0xF8FF).contains(scalar.value) { return false }
        return true
    }
}
