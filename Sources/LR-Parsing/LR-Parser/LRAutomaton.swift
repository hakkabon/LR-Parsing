import Grammar

/// A stable, inspectable state in a generated LR automaton.
public struct LRState: Hashable, CustomStringConvertible {
    public let id: Int
    public let items: Set<LRItem>

    public init(id: Int, items: Set<LRItem>) {
        self.id = id
        self.items = items
    }

    public var description: String {
        (["State \(id):"] + items.map(\.description).sorted().map { "  \($0)" }).joined(separator: "\n")
    }
}

public struct LRTransition: Hashable {
    public let source: Int
    public let symbol: Symbol
    public let target: Int

    public init(source: Int, symbol: Symbol, target: Int) {
        self.source = source
        self.symbol = symbol
        self.target = target
    }
}

public struct LRConflict: Hashable, CustomStringConvertible {
    public enum Kind: String, Hashable {
        case shiftReduce = "shift/reduce"
        case reduceReduce = "reduce/reduce"
        case shiftShift = "shift/shift"
        case accept = "accept/action"
    }

    public let kind: Kind
    public let state: Int
    public let lookahead: Terminal
    public let actions: [LRAction]
    /// A shortest terminal sequence reaching the conflict state, followed by
    /// the conflicting lookahead (except when it is EOF).
    public let witness: [Terminal]

    public init(kind: Kind, state: Int, lookahead: Terminal, actions: [LRAction], witness: [Terminal] = []) {
        self.kind = kind
        self.state = state
        self.lookahead = lookahead
        self.actions = actions
        self.witness = witness
    }

    public var description: String {
        "\(kind.rawValue) in state \(state) on \(lookahead): \(actions.map(\.description).joined(separator: " / "))"
    }
}

/// Complete output of LR generation. Conflicted grammars still produce this
/// artifact so diagnostics and states remain inspectable.
public struct LRAutomaton {
    public let states: [LRState]
    public let transitions: [LRTransition]
    public let actionTable: LRActionTable
    public let gotoTable: LRGotoTable
    public let conflicts: [LRConflict]

    public init(states: [LRState], transitions: [LRTransition], actionTable: LRActionTable, gotoTable: LRGotoTable, conflicts: [LRConflict]) {
        self.states = states
        self.transitions = transitions
        self.actionTable = actionTable
        self.gotoTable = gotoTable
        self.conflicts = conflicts
    }

    public func state(_ id: Int) -> LRState? { states.first { $0.id == id } }
}
