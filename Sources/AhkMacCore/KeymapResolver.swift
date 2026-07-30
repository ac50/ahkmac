/// Resolves a pressed key against the keymap rules.
///
/// A rule matches when its source key code equals the pressed key, its
/// source modifiers are a subset of the pressed modifiers, and its scope
/// contains the current app. Among matches, the rule with the most modifiers
/// wins; on a tie the one with the highest scope tier wins; on a further tie
/// the one defined first wins. Unconsumed modifiers pass through via
/// KeymapRule.chordOutput.
public struct KeymapResolver {
    private let rulesByKey: [UInt16: [KeymapRule]]

    public init(rules: [KeymapRule]) {
        self.rulesByKey = Dictionary(grouping: rules, by: { $0.source.keyCode })
    }

    public func resolve(keyCode: UInt16, pressed: Modifiers, app: String?) -> KeymapRule? {
        let app = app?.lowercased()
        var best: KeymapRule?
        for rule in rulesByKey[keyCode] ?? []
        where pressed.isSuperset(of: rule.source.modifiers) && rule.scope.matches(app: app) {
            guard let current = best else { best = rule; continue }
            if (rule.source.modifiers.count, rule.scope.level)
                > (current.source.modifiers.count, current.scope.level) {
                best = rule
            }
        }
        return best
    }
}
