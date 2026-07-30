/// What to do when a hotstring fires. The caller must suppress the event
/// that produced the decisive character and synthesize `backspaces`
/// backspace presses, then act on `output`: for `.text(text, repost:)`,
/// type `text` and, if `repost` is set (end-char mode), re-post a copy of
/// the suppressed original event afterwards; for `.macro(index)`, run
/// `Config.macros[index]`.
public struct Firing: Equatable {
    public let backspaces: Int
    public let output: Output

    public enum Output: Equatable {
        case text(String, repost: Bool)
        case macro(Int)
    }

    public init(backspaces: Int, output: Output) {
        self.backspaces = backspaces
        self.output = output
    }
}

/// Tracks recently typed characters and decides when a hotstring fires.
/// Matching is by suffix (a trigger also fires mid-word, like AHK's `?`
/// option); the longest matching trigger wins. End chars are ordinary
/// buffer content — triggers may contain escaped punctuation ("e\-mail")
/// — but they additionally check end-char-mode triggers first; when the
/// same keystroke could fire both modes, end-char mode wins.
public final class HotstringEngine {
    private let rules: [HotstringRule]
    private let maxTriggerLength: Int
    private var buffer: [Character] = []
    private var activeApp: String?

    public init(rules: [HotstringRule]) {
        self.rules = rules
        self.maxTriggerLength = rules.map { $0.trigger.count }.max() ?? 0
    }

    /// The frontmost app's bundle ID (any case). Changing apps clears the
    /// buffer — a half-typed word in one app must not fire in another.
    public func setActiveApp(_ app: String?) {
        let normalized = app?.lowercased()
        if normalized != activeApp {
            activeApp = normalized
            buffer.removeAll()
        }
    }

    /// Feed one typed character; nil means "let the event through".
    public func handleCharacter(_ ch: Character) -> Firing? {
        if HotstringRule.endChars.contains(ch) {
            if let rule = longestMatch(immediate: false) {
                buffer.removeAll()
                return fire(rule, backspaces: rule.trigger.count, endChar: true)
            }
        } else if !Self.isTypable(ch) {
            buffer.removeAll()
            return nil
        }
        append(ch)
        if let rule = longestMatch(immediate: true) {
            buffer.removeAll()
            return fire(rule, backspaces: rule.trigger.count - 1, endChar: false)
        }
        return nil
    }

    private func fire(_ rule: HotstringRule, backspaces: Int, endChar: Bool) -> Firing {
        switch rule.action {
        case .text(let text):
            return Firing(backspaces: backspaces, output: .text(text, repost: endChar))
        case .macro(let index):
            return Firing(backspaces: backspaces, output: .macro(index))
        }
    }

    private func append(_ ch: Character) {
        buffer.append(ch)
        if buffer.count > maxTriggerLength {
            buffer.removeFirst(buffer.count - maxTriggerLength)
        }
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
            && rule.scope.matches(app: activeApp)
            && rule.trigger.count <= buffer.count
            && buffer.suffix(rule.trigger.count).elementsEqual(rule.trigger) {
            guard let current = best else { best = rule; continue }
            if (rule.trigger.count, rule.scope.level) > (current.trigger.count, current.scope.level) {
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
