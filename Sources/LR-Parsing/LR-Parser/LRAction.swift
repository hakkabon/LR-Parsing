//
//  LRAction.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// The operations the parser can take
enum LRAction: CustomStringConvertible {
    case shift(Int)          // Shift input, go to State ID
    case reduce(Production)  // Reduce stack using Production
    case accept              // Successfully parsed
    
    var description: String {
        switch self {
        case .shift(let s): return "s\(s)"
        case .reduce(let p): return "r(\(p.goal))"
        case .accept: return "acc"
        }
    }
}
