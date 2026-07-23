/// Resolves a pressed key against the keymap rules.
///
/// A rule matches when its source key code equals the pressed key and its
/// source modifiers are a subset of the pressed modifiers. Among matches
/// the rule with the most modifiers wins; on a tie the one defined first
/// wins. Unconsumed modifiers pass through via KeymapRule.output.
public struct KeymapResolver {
    private let rulesByKey: [UInt16: [KeymapRule]]

    public init(rules: [KeymapRule]) {
        self.rulesByKey = Dictionary(grouping: rules, by: { $0.source.keyCode })
    }

    public func resolve(keyCode: UInt16, pressed: Modifiers) -> KeymapRule? {
        var best: KeymapRule?
        for rule in rulesByKey[keyCode] ?? []
        where pressed.isSuperset(of: rule.source.modifiers) {
            if best == nil || rule.source.modifiers.count > best!.source.modifiers.count {
                best = rule
            }
        }
        return best
    }
}
