import Grammar

/// A stable, inspectable state in a generated LR automaton.
public struct LRState: Hashable, CustomStringConvertible {
    public let id: Int
    public let identity: LRArtifactID
    public let items: Set<LRItem>

    public init(id: Int, items: Set<LRItem>, identity: LRArtifactID? = nil) {
        self.id = id
        self.items = items
        self.identity = identity ?? LRArtifactID(rawValue: "state:" + items.map(\.identity.rawValue).sorted().joined(separator: "|"))
    }

    public var description: String {
        (["State \(id):"] + items.map(\.description).sorted().map { "  \($0)" }).joined(separator: "\n")
    }
}

public struct LRTransition: Hashable {
    public let identity: LRArtifactID
    public let source: Int
    public let symbol: Symbol
    public let target: Int

    public init(source: Int, symbol: Symbol, target: Int, identity: LRArtifactID? = nil) {
        self.source = source
        self.symbol = symbol
        self.target = target
        self.identity = identity ?? LRArtifactID(rawValue: "transition:\(source)-\(symbol.lrStableKey)->\(target)")
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
    public let identity: LRArtifactID
    public let state: Int
    public let lookahead: Terminal
    public let actions: [LRAction]
    /// A shortest terminal sequence reaching the conflict state, followed by
    /// the conflicting lookahead (except when it is EOF).
    public let witness: [Terminal]

    public init(kind: Kind, state: Int, lookahead: Terminal, actions: [LRAction], witness: [Terminal] = [], identity: LRArtifactID? = nil) {
        self.kind = kind
        self.state = state
        self.lookahead = lookahead
        self.actions = actions
        self.witness = witness
        self.identity = identity ?? LRArtifactID(rawValue: "conflict:\(state):\(lookahead.description):\(actions.map(\.lrStableKey).sorted().joined(separator: "|"))")
    }

    public var description: String {
        "\(kind.rawValue) in state \(state) on \(lookahead): \(actions.map(\.description).joined(separator: " / "))"
    }
}

extension LRConflict: Comparable {
    
    public static func < (lhs: LRConflict, rhs: LRConflict) -> Bool {
        return lhs.state == rhs.state ? lhs.lookahead.lrStableKey < rhs.lookahead.lrStableKey : lhs.state < rhs.state
    }
}


/// Complete output of LR generation. Conflicted grammars still produce this
/// artifact so diagnostics and states remain inspectable.
public struct LRAutomaton {
    public let productions: [LRProductionArtifact]
    public let states: [LRState]
    public let transitions: [LRTransition]
    public let actionTable: LRActionTable
    public let gotoTable: LRGotoTable
    public let conflicts: [LRConflict]

    public init(states: [LRState], transitions: [LRTransition], actionTable: LRActionTable, gotoTable: LRGotoTable, conflicts: [LRConflict], productions: [LRProductionArtifact]? = nil) {
        self.productions = productions ?? Dictionary(grouping: states.flatMap(\.items).map { LRProductionArtifact(production: $0.production) }, by: \.identity).values.compactMap(\.first).sorted { $0.identity < $1.identity }
        self.states = states
        self.transitions = transitions
        self.actionTable = actionTable
        self.gotoTable = gotoTable
        self.conflicts = conflicts
    }

    public func state(_ id: Int) -> LRState? { states.first { $0.id == id } }
    public func state(identity: LRArtifactID) -> LRState? { states.first { $0.identity == identity } }
    public func conflict(identity: LRArtifactID) -> LRConflict? { conflicts.first { $0.identity == identity } }
    public func production(identity: LRArtifactID) -> LRProductionArtifact? { productions.first { $0.identity == identity } }
}
