//
//  TableGenerator.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

class LRTableGenerator {
    let grammar: Grammar
    let algorithm: LRParser.Algorithm
    let augmentedStart = NonTerminal(name: "S'")
    var firstSets: [Symbol: Set<Symbol>]
    var followSets: [NonTerminal: Set<Symbol>]
    
    init(grammar: Grammar, algorithm: LRParser.Algorithm) {
        self.grammar = grammar
        self.algorithm = algorithm
        // Pre-calculate sets
        (self.firstSets, self.followSets) = grammar.firstAndFollow()
    }
    
    func generate() -> (LRTable, [Int: Set<LRItem>])? {
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
        
        // 2. Populate Table
        for (stateId, items) in states.enumerated() {
            if table.action[stateId] == nil { table.action[stateId] = [:] }
            
            // --- A. SHIFT & GOTO ACTIONS ---
            // Group items by their next symbol to determine transitions
            let nextSymbols = Set(items.compactMap { $0.nextSymbol })
            
            for symbol in nextSymbols {
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
                    print("Error: Transition to unknown state in generation.")
                    return nil
                }
                switch symbol {
                case .terminal(let t):
                    // Conflict Check (Shift/Reduce) happens at insertion
                    addShift(to: &table, state: stateId, terminal: t, target: nextStateId)
                case .nonTerminal(let nt):
                    if table.gotoTable[stateId] == nil { table.gotoTable[stateId] = [:] }
                    table.gotoTable[stateId]?[nt] = nextStateId
                default: break
                }
            }
            
            // --- B. REDUCE ACTIONS ---
            for item in items {
                // If dot is at end: A -> α •
                if item.nextSymbol == nil {
                    if item.production.goal == augmentedStart {
                        // Accept: S' -> S •
                        table.action[stateId]?[.meta(.eof)] = .accept
                    } else {
                        // Determine which terminals trigger reduction
                        let reduceTerminals = getReduceTerminals(for: item, at: item.production.goal)
                        
                        for term in reduceTerminals {
                            if case .meta(let m) = term, m == .eps { continue } // Never reduce on epsilon
                            
                            // Attempt to add Reduce
                            let conflict = addReduce(to: &table, state: stateId, terminal: term, production: item.production)
                            if conflict { return nil } // Abort on conflict
                        }
                    }
                }
            }
        }
        
        return (table, Dictionary(uniqueKeysWithValues: states.enumerated().map { ($0, $1) }))
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
            
            for sym in symbols {
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
            
            for sym in symbols {
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
