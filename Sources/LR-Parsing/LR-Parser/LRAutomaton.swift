//
//  LRAutomaton.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

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
    public let candidates: [LRActionCandidate]
    public let decision: LRActionDecision?
    /// A shortest terminal sequence reaching the conflict state, followed by
    /// the conflicting lookahead (except when it is EOF).
    public let witness: [Terminal]

    public init(kind: Kind, state: Int, lookahead: Terminal, actions: [LRAction], witness: [Terminal] = [], identity: LRArtifactID? = nil, candidates: [LRActionCandidate] = [], decision: LRActionDecision? = nil) {
        self.kind = kind
        self.state = state
        self.lookahead = lookahead
        self.actions = actions
        self.witness = witness
        self.candidates = candidates
        self.decision = decision
        self.identity = identity ?? LRArtifactID(rawValue: "conflict:\(state):\(lookahead.description):\(actions.map(\.lrStableKey).sorted().joined(separator: "|"))")
    }

    public var description: String {
        "\(kind.rawValue) in state \(state) on \(lookahead): \(actions.map(\.description).joined(separator: " / "))"
    }
}

<<<<<<< HEAD
extension LRConflict: Comparable {
    
=======
    public var status: LRActionDecisionStatus { decision?.status ?? .unresolved }
    public var isResolved: Bool { status == .resolved }

>>>>>>> dev-branch
    public static func < (lhs: LRConflict, rhs: LRConflict) -> Bool {
        if lhs.state != rhs.state { return lhs.state < rhs.state }
        if lhs.lookahead.lrStableKey != rhs.lookahead.lrStableKey { return lhs.lookahead.lrStableKey < rhs.lookahead.lrStableKey }
        return lhs.identity < rhs.identity
    }
}


/// Complete output of LR generation. Conflicted grammars still produce this
/// artifact so diagnostics and states remain inspectable.
public struct LRAutomaton {
    public let productions: [LRProductionArtifact]
    public let states: [LRState]
    public let transitions: [LRTransition]
    public let actionTable: LRActionTable
    /// All candidates and origins considered before choosing each ACTION cell.
    public let actionCandidates: LRActionCandidateTable
    /// The explicit deterministic selection made for every ACTION cell.
    public let actionDecisions: LRActionDecisionTable
    public let gotoTable: LRGotoTable
    public let conflicts: [LRConflict]
    public var resolvedConflicts: [LRConflict] { conflicts.filter(\.isResolved) }
    public var unresolvedConflicts: [LRConflict] { conflicts.filter { !$0.isResolved } }

    public init(states: [LRState], transitions: [LRTransition], actionTable: LRActionTable, gotoTable: LRGotoTable, conflicts: [LRConflict], productions: [LRProductionArtifact]? = nil, actionCandidates: LRActionCandidateTable = [:], actionDecisions: LRActionDecisionTable = [:]) {
        self.productions = productions ?? Dictionary(grouping: states.flatMap(\.items).map { LRProductionArtifact(production: $0.production) }, by: \.identity).values.compactMap(\.first).sorted { $0.identity < $1.identity }
        self.states = states
        self.transitions = transitions
        self.actionTable = actionTable
        self.actionCandidates = actionCandidates
        self.actionDecisions = actionDecisions
        self.gotoTable = gotoTable
        self.conflicts = conflicts
    }

    public func state(_ id: Int) -> LRState? { states.first { $0.id == id } }
    public func state(identity: LRArtifactID) -> LRState? { states.first { $0.identity == identity } }
    public func conflict(identity: LRArtifactID) -> LRConflict? { conflicts.first { $0.identity == identity } }
    public func production(identity: LRArtifactID) -> LRProductionArtifact? { productions.first { $0.identity == identity } }
}
