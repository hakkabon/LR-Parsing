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
struct LRTable {
    // Action: (State ID, Terminal) -> Action
    var action: [Int: [Terminal: LRAction]] = [:]
    
    // Goto: (State ID, NonTerminal) -> Next State ID
    var gotoTable: [Int: [NonTerminal: Int]] = [:]
}
