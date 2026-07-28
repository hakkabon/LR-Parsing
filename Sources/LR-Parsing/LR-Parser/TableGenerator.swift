//
//  TableGenerator.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

public final class LRTableGenerator {
    let grammar: Grammar
    let algorithm: LRParser.Algorithm
    let precedence: LRPrecedenceSpecification?
    let resolutionPolicy: (any LRConflictResolutionPolicy)?
    let augmentedStart = NonTerminal(name: "S'")
    var firstSets: [Symbol: Set<Symbol>]
    var followSets: [NonTerminal: Set<Symbol>]
    
    public init(grammar: Grammar, algorithm: LRParser.Algorithm, precedence: LRPrecedenceSpecification? = nil, resolutionPolicy: (any LRConflictResolutionPolicy)? = nil) {
        self.grammar = grammar
        self.algorithm = algorithm
        self.precedence = precedence
        self.resolutionPolicy = resolutionPolicy
        // Pre-calculate sets
        (self.firstSets, self.followSets) = grammar.firstAndFollow()
    }
    
    public func generate() -> LRAutomaton {
        // 1. Generate Canonical Collection of States
        var states: [Set<LRItem>]
        
        switch algorithm {
        case .lr0, .slr:
            states = generateLR0States()
        case .lr1:
            states = generateLR1States()
        case .lalr:
            let lr1States = generateLR1States()
            states = mergeToLALR(lr1States)
        }
        
        // Map States to IDs
        // We use an array index as ID.
        // For transitions, we need a quick lookup of State -> ID
        // Since Set<LRItem> is hashable, we can use a dictionary.
        var stateMap = [Set<LRItem>: Int]()
        for (i, s) in states.enumerated() { stateMap[s] = i }
        
        // For LALR, also build a core-keyed map so that goto results
        // (which carry LR(1) lookaheads that may not match the merged
        // LALR sets exactly) can still be resolved to the correct state.
        var coreMap = [Set<LRItem.Core>: Int]()
        if algorithm == .lalr {
            for (i, s) in states.enumerated() {
                coreMap[Set(s.map { $0.core })] = i
            }
        }
        
        var table = LRTable()
        var transitions: [LRTransition] = []
        var candidates: LRActionCandidateTable = [:]
        
        // 2. Populate Table
        for (stateId, items) in states.enumerated() {
            if table.action[stateId] == nil { table.action[stateId] = [:] }
            
            // --- A. SHIFT & GOTO ACTIONS ---
            // Group items by their next symbol to determine transitions
            let nextSymbols = Set(items.compactMap { $0.nextSymbol })
            
            for symbol in nextSymbols.sorted(by: { $0.lrStableKey < $1.lrStableKey }) {
                // Calculate destination state
                let nextStateItems = gotoState(items, symbol)
                
                // First try an exact match; for LALR fall back to core-only
                // matching because the goto produces LR(1) items whose merged
                // lookaheads may differ from the stored LALR state.
                let nextStateId: Int
                if let direct = stateMap[nextStateItems] {
                    nextStateId = direct
                } else if algorithm == .lalr,
                          let coreId = coreMap[Set(nextStateItems.map { $0.core })] {
                    nextStateId = coreId
                } else {
                    continue
                }
                transitions.append(LRTransition(source: stateId, symbol: symbol, target: nextStateId))
                switch symbol {
                case .terminal(let t):
                    for item in items.filter({ $0.nextSymbol == symbol }).sorted(by: { $0.identity < $1.identity }) {
                        add(.shift(nextStateId), from: item, because: .terminalTransition(symbol), state: stateId, terminal: t, candidates: &candidates)
                    }
                case .nonTerminal(let nt):
                    if table.gotoTable[stateId] == nil { table.gotoTable[stateId] = [:] }
                    table.gotoTable[stateId]?[nt] = nextStateId
                default: break
                }
            }
            
            // --- B. REDUCE ACTIONS ---
            for item in items.sorted(by: { $0.identity < $1.identity }) {
                // If dot is at end: A -> α •
                if item.nextSymbol == nil {
                    if item.production.goal == augmentedStart {
                        // Accept: S' -> S •
                        add(.accept, from: item, because: .augmentedStart, state: stateId, terminal: .meta(.eof), candidates: &candidates)
                    } else {
                        // Determine which terminals trigger reduction
                        let reduceTerminals = getReduceTerminals(for: item, at: item.production.goal)
                        
                        for term in reduceTerminals.sorted(by: { $0.lrStableKey < $1.lrStableKey }) {
                            if case .meta(let m) = term, m == .eps { continue } // Never reduce on epsilon
                            
                            add(.reduce(item.production), from: item, because: reductionReason(for: item), state: stateId, terminal: term, candidates: &candidates)
                        }
                    }
                }
            }
        }
        
        var rawConflicts: [(Int, Terminal, [LRAction], [LRActionCandidate])] = []
        var normalizedCandidates: LRActionCandidateTable = [:]
        var decisions: LRActionDecisionTable = [:]
        for state in candidates.keys.sorted() {
            for terminal in candidates[state, default: [:]].keys.sorted(by: { $0.lrStableKey < $1.lrStableKey }) {
                let origins = (candidates[state]?[terminal] ?? []).reduce(into: [LRActionCandidate]()) { result, candidate in
                    if !result.contains(where: { $0.identity == candidate.identity }) { result.append(candidate) }
                }.sorted { $0.identity < $1.identity }
                normalizedCandidates[state, default: [:]][terminal] = origins
                let actions = origins.map(\.action)
                let unique = actions.reduce(into: [LRAction]()) { if !$0.contains($1) { $0.append($1) } }
                let selection = preferredAction(in: unique, candidates: origins, state: state, on: terminal)
                let decision = LRActionDecision(state: state, lookahead: terminal, candidates: origins, selectedAction: selection.action, resolution: selection.resolution, status: selection.status)
                decisions[state, default: [:]][terminal] = decision
                if let selected = decision.selectedAction { table.action[state, default: [:]][terminal] = selected }
                if unique.count > 1 { rawConflicts.append((state, terminal, unique, origins)) }
            }
        }
        let prefixes = shortestPrefixes(transitions: transitions)
        let stateArtifacts = states.enumerated().map { LRState(id: $0.offset, items: $0.element) }
        let stateIdentities = Dictionary(uniqueKeysWithValues: stateArtifacts.map { ($0.id, $0.identity) })
        var conflicts: [LRConflict] = []
        for (state, terminal, actions, origins) in rawConflicts {
            var witness = prefixes[state] ?? []
            if terminal != .meta(.eof) { witness.append(terminal) }
            let stateKey = stateIdentities[state]?.rawValue ?? String(state)
            let actionKey = actions.map(\.lrStableKey).sorted().joined(separator: "|")
            let identity = LRArtifactID(rawValue: "conflict:\(stateKey):\(terminal.lrStableKey):\(actionKey)")
            conflicts.append(LRConflict(kind: conflictKind(actions), state: state, lookahead: terminal, actions: actions, witness: witness, identity: identity, candidates: origins, decision: decisions[state]?[terminal]))
        }
        conflicts.sort()

        return LRAutomaton(
            states: stateArtifacts,
            transitions: transitions.map { transition in
                let source = stateIdentities[transition.source]?.rawValue ?? String(transition.source)
                let target = stateIdentities[transition.target]?.rawValue ?? String(transition.target)
                return LRTransition(source: transition.source, symbol: transition.symbol, target: transition.target, identity: LRArtifactID(rawValue: "transition:\(source)-\(transition.symbol.lrStableKey)->\(target)"))
            }.sorted { $0.identity < $1.identity },
            actionTable: table.action,
            gotoTable: table.gotoTable,
            conflicts: conflicts,
            actionCandidates: normalizedCandidates,
            actionDecisions: decisions
        )
    }
    
    // MARK: - Helper: Resolve Reduction Lookaheads
    
    private func getReduceTerminals(for item: LRItem, at nonTerminal: NonTerminal) -> Set<Terminal> {
        var symbols = Set<Terminal>()
        
        switch algorithm {
        case .lr0:
            // LR(0): Reduce on EVERYTHING (Grammar terminals + EOF)
            // Ideally iterate all known terminals. Using a wildcard concept is better,
            // but here we just collect all from grammar for simplicity.
            // (Assuming caller handles fetching all valid terminals)
            return getAllTerminals()
            
        case .slr:
            // SLR: Reduce on Follow(A)
            let follow = followSets[nonTerminal] ?? []
            for s in follow {
                if case .terminal(let t) = s { symbols.insert(t) }
            }
            
        case .lr1, .lalr:
            // LR(1)/LALR: Reduce on specific item lookahead
            for s in item.lookahead {
                if case .terminal(let t) = s { symbols.insert(t) }
            }
        }
        return symbols
    }
    
    // MARK: - State Generation Logic
    
    private func generateLR0States() -> [Set<LRItem>] {
        let startProd = Production(goal: augmentedStart, rule: [.nonTerminal(grammar.start)])
        let startItem = LRItem(production: startProd, dotIndex: 0) // No lookahead needed
        
        // Canonical Collection Loop (same as previous LR0 implementation)
        var states = [closure([startItem])]
        var processed = 0
        
        while processed < states.count {
            let current = states[processed]
            let symbols = Set(current.compactMap { $0.nextSymbol })
            
            for sym in symbols.sorted(by: { $0.lrStableKey < $1.lrStableKey }) {
                let next = gotoState(current, sym)
                if !next.isEmpty && !states.contains(next) {
                    states.append(next)
                }
            }
            processed += 1
        }
        return states
    }
    
    private func generateLR1States() -> [Set<LRItem>] {
        let startProd = Production(goal: augmentedStart, rule: [.nonTerminal(grammar.start)])
        // LR(1) Start Item: [S' -> . S, {EOF}]
        let startItem = LRItem(production: startProd, dotIndex: 0, lookahead: [.terminal(.meta(.eof))])
        
        var states = [closureLR1([startItem])]
        var processed = 0
        
        while processed < states.count {
            let current = states[processed]
            let symbols = Set(current.compactMap { $0.nextSymbol })
            
            for sym in symbols.sorted(by: { $0.lrStableKey < $1.lrStableKey }) {
                let next = gotoStateLR1(current, sym)
                if !next.isEmpty && !states.contains(next) {
                    states.append(next)
                }
            }
            processed += 1
        }
        return states
    }
    
    // MARK: - LALR Merging
    
    private func mergeToLALR(_ lr1States: [Set<LRItem>]) -> [Set<LRItem>] {
        // Group states by Core (ignoring lookaheads)
        var coreMap = [Set<LRItem.Core>: Int]() // Map CoreSet -> Index in result array
        var mergedStates = [Set<LRItem>]()
        
        for state in lr1States {
            let cores = Set(state.map { $0.core })
            
            if let existingIndex = coreMap[cores] {
                // Merge lookaheads into existing state
                let existingState = mergedStates[existingIndex]
                var newState = Set<LRItem>()
                
                // For every item in existing, find match in current and union lookaheads
                for item in existingState {
                    // Find corresponding item in the new state (same core)
                    if let match = state.first(where: { $0.core == item.core }) {
                        newState.insert(item.withLookahead(item.lookahead.union(match.lookahead)))
                    } else {
                        newState.insert(item)
                    }
                }
                mergedStates[existingIndex] = newState
            } else {
                // New core configuration found
                coreMap[cores] = mergedStates.count
                mergedStates.append(state)
            }
        }
        
        // IMPORTANT: LALR GOTO fix up
        // After merging, the 'goto' transitions must point to the new merged sets.
        // Because we return [Set<LRItem>], the main loop's 'gotoState' will generate
        // a set that exactly matches one of these merged sets (mathematically guaranteed).
        return mergedStates
    }

    // MARK: - Closures & Goto
    
    // Standard LR(0) Closure
    private func closure(_ items: Set<LRItem>) -> Set<LRItem> {
        var set = items
        var changed = true
        while changed {
            changed = false
            for item in set {
                guard let sym = item.nextSymbol, case .nonTerminal(let B) = sym else { continue }
                for prod in grammar.productions where prod.goal == B {
                    let new = LRItem(production: prod, dotIndex: 0)
                    if !set.contains(new) { set.insert(new); changed = true }
                }
            }
        }
        return set
    }
    
    // LR(1) Closure
    private func closureLR1(_ items: Set<LRItem>) -> Set<LRItem> {
        var set = items
        var changed = true
        while changed {
            changed = false
            for item in set {
                // Item: [A -> α . B β, {a}]
                guard let sym = item.nextSymbol, case .nonTerminal(let B) = sym else { continue }
                
                // Calculate First(βa)
                // β is the part of the rule AFTER B
                let betaIndex = item.dotIndex + 1
                let beta = Array(item.production.rule.dropFirst(betaIndex))
                
                // We need to compute First(β)
                // If β is nullable, we also include 'a' (the lookahead from the parent item)
                var lookaheadsForB = grammar.first(of: beta, using: self.firstSets)
                
                // Handle epsilon logic manually for the set combination
                let containsEps = lookaheadsForB.contains(.terminal(.meta(.eps)))
                lookaheadsForB.remove(.terminal(.meta(.eps)))
                
                if containsEps || beta.isEmpty {
                    lookaheadsForB.formUnion(item.lookahead)
                }
                
                // For each production B -> γ
                for prod in grammar.productions where prod.goal == B {
                    // Create new item: [B -> . γ, First(βa)]
                    // Note: We might already have this core, but with different lookaheads.
                    // We need to find if it exists and merge lookaheads, or insert new.
                    
                    let candidate = LRItem(production: prod, dotIndex: 0, lookahead: lookaheadsForB)
                    
                    // Custom set insertion logic for LR1:
                    // If we have an item with same Core, merge lookaheads.
                    if let existing = set.first(where: { $0.core == candidate.core }) {
                        if !candidate.lookahead.isSubset(of: existing.lookahead) {
                            set.remove(existing)
                            set.insert(existing.withLookahead(existing.lookahead.union(candidate.lookahead)))
                            changed = true
                        }
                    } else {
                        set.insert(candidate)
                        changed = true
                    }
                }
            }
        }
        return set
    }
    
    // Wrappers for Goto based on algo
    private func gotoState(_ items: Set<LRItem>, _ sym: Symbol) -> Set<LRItem> {
        if algorithm == .lr0 || algorithm == .slr {
            var next = Set<LRItem>()
            for i in items where i.nextSymbol == sym { next.insert(i.advanced()) }
            return closure(next)
        } else {
            return gotoStateLR1(items, sym)
        }
    }
    
    private func gotoStateLR1(_ items: Set<LRItem>, _ sym: Symbol) -> Set<LRItem> {
        var next = Set<LRItem>()
        for i in items where i.nextSymbol == sym { next.insert(i.advanced()) }
        return closureLR1(next)
    }

    // MARK: - Table Population Utilities

    private func add(_ action: LRAction, from item: LRItem, because reason: LRActionReason, state: Int, terminal: Terminal, candidates: inout LRActionCandidateTable) {
        candidates[state, default: [:]][terminal, default: []].append(
            LRActionCandidate(state: state, lookahead: terminal, action: action, item: item, reason: reason)
        )
    }

    private func reductionReason(for item: LRItem) -> LRActionReason {
        switch algorithm {
        case .lr0: .lr0Reduction
        case .slr: .slrFollow(item.production.goal)
        case .lr1, .lalr: .itemLookahead
        }
    }

    private func preferredAction(in actions: [LRAction], candidates: [LRActionCandidate], state: Int, on lookahead: Terminal) -> (action: LRAction?, resolution: LRActionResolution, status: LRActionDecisionStatus) {
        if actions.count == 1 { return (actions[0], .soleAction, .resolved) }
        if let precedenceSelection = precedenceSelection(in: actions, on: lookahead) { return precedenceSelection }
        if let policySelection = policySelection(in: actions, candidates: candidates, state: state, on: lookahead) { return policySelection }
        if let accept = actions.first(where: { if case .accept = $0 { return true }; return false }) {
            return (accept, .preferAcceptFallback, .unresolved)
        }
        if let shift = actions.first(where: { if case .shift = $0 { return true }; return false }) {
            return (shift, .preferShiftFallback, .unresolved)
        }
        return (actions[0], .generationOrderFallback, .unresolved)
    }

    private func policySelection(in actions: [LRAction], candidates: [LRActionCandidate], state: Int, on lookahead: Terminal) -> (action: LRAction?, resolution: LRActionResolution, status: LRActionDecisionStatus)? {
        guard let resolutionPolicy else { return nil }
        let context = LRConflictResolutionContext(state: state, lookahead: lookahead, candidates: candidates, actions: actions)
        guard let proposal = resolutionPolicy.resolve(context) else { return nil }
        if let selected = proposal.selectedAction, !actions.contains(selected) { return nil }
        return (proposal.selectedAction, .policy(name: resolutionPolicy.name, explanation: proposal.explanation), .resolved)
    }

    private func precedenceSelection(in actions: [LRAction], on lookahead: Terminal) -> (action: LRAction?, resolution: LRActionResolution, status: LRActionDecisionStatus)? {
        guard let precedence else { return nil }
        let shifts = actions.filter { if case .shift = $0 { return true }; return false }
        let reductions = actions.compactMap { action -> (LRAction, Production)? in
            if case .reduce(let production) = action { return (action, production) }
            return nil
        }

        if shifts.count == 1, reductions.count == 1, actions.count == 2,
           let shiftPrecedence = precedence.precedence(of: lookahead),
           let reducePrecedence = precedence.precedence(of: reductions[0].1) {
            if shiftPrecedence.level > reducePrecedence.level {
                return (shifts[0], .higherPrecedence(selected: shiftPrecedence.level, rejected: reducePrecedence.level), .resolved)
            }
            if reducePrecedence.level > shiftPrecedence.level {
                return (reductions[0].0, .higherPrecedence(selected: reducePrecedence.level, rejected: shiftPrecedence.level), .resolved)
            }
            switch shiftPrecedence.associativity {
            case .left: return (reductions[0].0, .leftAssociative(level: shiftPrecedence.level), .resolved)
            case .right: return (shifts[0], .rightAssociative(level: shiftPrecedence.level), .resolved)
            case .nonAssociative: return (nil, .nonAssociative(level: shiftPrecedence.level), .resolved)
            }
        }

        if reductions.count == actions.count {
            let ranked = reductions.compactMap { action, production in precedence.precedence(of: production).map { (action, $0) } }
                .sorted { $0.1.level > $1.1.level }
            if ranked.count == reductions.count, ranked.count > 1, ranked[0].1.level > ranked[1].1.level {
                return (ranked[0].0, .higherPrecedence(selected: ranked[0].1.level, rejected: ranked[1].1.level), .resolved)
            }
        }
        return nil
    }

    private func conflictKind(_ actions: [LRAction]) -> LRConflict.Kind {
        let shifts = actions.filter { if case .shift = $0 { return true }; return false }.count
        let reductions = actions.filter { if case .reduce = $0 { return true }; return false }.count
        if shifts > 0 && reductions > 0 { return .shiftReduce }
        if reductions > 1 { return .reduceReduce }
        if shifts > 1 { return .shiftShift }
        return .accept
    }

    /// Shortest terminal yield along automaton paths. Nonterminal edges are
    /// weighted by their shortest derivable terminal sequence.
    private func shortestPrefixes(transitions: [LRTransition]) -> [Int: [Terminal]] {
        var yields: [NonTerminal: [Terminal]] = [:]
        var changed = true
        while changed {
            changed = false
            for production in grammar.productions {
                var candidate: [Terminal] = []
                var known = true
                for symbol in production.rule {
                    switch symbol {
                    case .terminal(let terminal): if !terminal.isEmpty { candidate.append(terminal) }
                    case .nonTerminal(let nonterminal):
                        guard let value = yields[nonterminal] else { known = false; break }
                        candidate += value
                    case .metaSymbol: known = false
                    }
                    if !known { break }
                }
                if known, yields[production.goal] == nil || candidate.count < yields[production.goal]!.count {
                    yields[production.goal] = candidate
                    changed = true
                }
            }
        }

        var best: [Int: [Terminal]] = [0: []]
        var pending = [0]
        while !pending.isEmpty {
            let source = pending.removeFirst()
            for edge in transitions where edge.source == source {
                let addition: [Terminal]
                switch edge.symbol {
                case .terminal(let terminal): addition = terminal.isEmpty ? [] : [terminal]
                case .nonTerminal(let nonterminal): guard let value = yields[nonterminal] else { continue }; addition = value
                case .metaSymbol: continue
                }
                let candidate = best[source, default: []] + addition
                if best[edge.target] == nil || candidate.count < best[edge.target]!.count {
                    best[edge.target] = candidate
                    pending.append(edge.target)
                }
            }
        }
        return best
    }
    
    private func addShift(to table: inout LRTable, state: Int, terminal: Terminal, target: Int) {
        if let existing = table.action[state]?[terminal] {
            // Check existing action
            switch existing {
            case .shift(let s):
                if s != target { print("Shift/Shift Conflict!") }
            case .reduce(_), .accept:
                print("Shift/Reduce Conflict in state \(state) on \(terminal). (Shift favored)")
            }
        }
        table.action[state]?[terminal] = .shift(target)
    }
    
    private func addReduce(to table: inout LRTable, state: Int, terminal: Terminal, production: Production) -> Bool {
        if let existing = table.action[state]?[terminal] {
            switch existing {
            case .shift(_):
                print("Shift/Reduce Conflict in state \(state) on \(terminal). Algorithm: \(algorithm)")
                // In generic generators, you usually favor shift.
                // However, returning 'true' (error) is safer for strictness.
                return true
            case .reduce(let p):
                if p != production {
                    print("Reduce/Reduce Conflict in state \(state) on \(terminal).")
                    return true
                }
            case .accept:
                return true
            }
        }
        table.action[state]?[terminal] = .reduce(production)
        return false
    }
    
    private func getAllTerminals() -> Set<Terminal> {
        var t = Set<Terminal>()
        t.insert(.meta(.eof))
        for p in grammar.productions {
            for s in p.rule {
                if case .terminal(let term) = s { t.insert(term) }
            }
        }
        return t
    }
}
