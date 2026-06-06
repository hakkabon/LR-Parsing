//
//  LRItem.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

struct LRItem: Hashable, CustomStringConvertible {
    let production: Production
    let dotIndex: Int
    
    // Lookahead set. Empty for LR(0)/SLR. Populated for LR(1)/LALR.
    var lookahead: Set<Symbol> = []

    // Helper for LALR merging: identifies items by rule position only
    struct Core: Hashable {
        let production: Production
        let dotIndex: Int
    }
    
    var core: Core { return Core(production: production, dotIndex: dotIndex) }

    var nextSymbol: Symbol? {
        if dotIndex < production.rule.count { return production.rule[dotIndex] }
        return nil
    }

    func advanced() -> LRItem {
        return LRItem(production: production, dotIndex: dotIndex + 1, lookahead: lookahead)
    }

    // Merge lookaheads for LALR
    func withLookahead(_ newLookahead: Set<Symbol>) -> LRItem {
        return LRItem(production: production, dotIndex: dotIndex, lookahead: newLookahead)
    }
    
    var description: String {
        var ruleStr = ""
        for (i, sym) in production.rule.enumerated() {
            if i == dotIndex { ruleStr += "• " }
            ruleStr += "\(sym) "
        }
        if dotIndex == production.rule.count { ruleStr += "•" }
        // Only show lookahead if it exists
        let laStr = lookahead.isEmpty ? "" : " , \(lookahead.map{ $0.description }.joined(separator: "/"))"
        return "[\(production.goal) -> \(ruleStr)\(laStr)]"
    }
}
