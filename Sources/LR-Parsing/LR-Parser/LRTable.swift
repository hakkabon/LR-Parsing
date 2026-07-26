//
//  LRTable.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// A simple structure to hold the generated tables
public typealias LRActionTable = [Int: [Terminal: LRAction]]
public typealias LRGotoTable = [Int: [NonTerminal: Int]]

public struct LRTable {
    // Action: (State ID, Terminal) -> Action
    public var action: LRActionTable = [:]
    
    // Goto: (State ID, NonTerminal) -> Next State ID
    public var gotoTable: LRGotoTable = [:]

    public init(action: LRActionTable = [:], gotoTable: LRGotoTable = [:]) {
        self.action = action
        self.gotoTable = gotoTable
    }

    /// Looks up the action for `token` in `state`.
    ///
    /// `action[state]` is keyed by the grammar's own terminals — which can be
    /// a `.regularExpression`/`.characterRange`/`.stringList` resolved from a
    /// `lexical { }` declaration, not just plain `.string` literals. `token`,
    /// on the other hand, is always a concrete lexeme the lexer produced.
    /// `Terminal`'s `==`/`Hashable` is strict structural equality (see the
    /// `Terminal` docs in the Grammar package), so a `.regularExpression`
    /// table entry and a `.string` token never land in the same dictionary
    /// bucket even when `entry.matches(token)` is `true` — a plain
    /// `action[state]?[token]` subscript would silently miss every lexical
    /// terminal. This checks the direct (fast, common) path first, then falls
    /// back to a `matches(_:)` scan of that state's actions.
    public func action(for token: Terminal, in state: Int) -> LRAction? {
        guard let actionsForState = action[state] else { return nil }
        if let direct = actionsForState[token] {
            return direct
        }
        for (terminal, candidateAction) in actionsForState where terminal.matches(token) {
            return candidateAction
        }
        return nil
    }
}
