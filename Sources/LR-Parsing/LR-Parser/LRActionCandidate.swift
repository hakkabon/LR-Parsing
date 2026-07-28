import Grammar

/// Why an ACTION-table candidate was generated.
public enum LRActionReason: Hashable, CustomStringConvertible {
    /// The item's dot precedes this terminal, producing a terminal transition.
    case terminalTransition(Symbol)
    /// LR(0) places a completed item's reduction on every terminal.
    case lr0Reduction
    /// SLR places a completed item's reduction on FOLLOW(goal).
    case slrFollow(NonTerminal)
    /// Canonical LR(1) or LALR uses the completed item's lookahead set.
    case itemLookahead
    /// The completed augmented-start item accepts on EOF.
    case augmentedStart

    var stableKey: String {
        switch self {
        case .terminalTransition(let symbol): "transition:\(symbol.lrStableKey)"
        case .lr0Reduction: "lr0-reduction"
        case .slrFollow(let nonterminal): "slr-follow:\(nonterminal.name)"
        case .itemLookahead: "item-lookahead"
        case .augmentedStart: "augmented-start"
        }
    }

    public var description: String {
        switch self {
        case .terminalTransition(let symbol): "the dot precedes \(symbol), creating a terminal transition"
        case .lr0Reduction: "LR(0) reduces completed items on every terminal"
        case .slrFollow(let nonterminal): "the lookahead belongs to FOLLOW(\(nonterminal.name))"
        case .itemLookahead: "the lookahead belongs to this completed LR item"
        case .augmentedStart: "the augmented start item is complete on end of input"
        }
    }
}

/// One candidate considered for an ACTION-table cell, before deduplication or
/// future precedence/associativity resolution.
public struct LRActionCandidate: Hashable, CustomStringConvertible {
    public let identity: LRArtifactID
    public let state: Int
    public let lookahead: Terminal
    public let action: LRAction
    public let item: LRItem
    public let reason: LRActionReason

    public init(state: Int, lookahead: Terminal, action: LRAction, item: LRItem, reason: LRActionReason, identity: LRArtifactID? = nil) {
        self.state = state
        self.lookahead = lookahead
        self.action = action
        self.item = item
        self.reason = reason
        self.identity = identity ?? LRArtifactID(rawValue: "candidate:\(item.identity.rawValue):\(lookahead.lrStableKey):\(action.lrStableKey):\(reason.stableKey)")
    }

    public var description: String { "\(action): \(reason)\n    origin: \(item)" }
}

public typealias LRActionCandidateTable = [Int: [Terminal: [LRActionCandidate]]]
