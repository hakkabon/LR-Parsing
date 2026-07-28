<<<<<<< HEAD
//
//  ParserOutcome.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/28.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
=======
>>>>>>> dev-branch
import Parser

/// LR specialization of the parser-independent deterministic result.
public typealias LRParseResult = DeterministicParseResult<LRParserTraceEvent>

/// Compatibility name retained for clients of the original LR API.
public typealias ParserOutcome = LRParseResult
public typealias ParserOutcomeStatus = ParseStatus
public typealias ParserDiagnostic = ParseDiagnostic

public enum RecoveryPolicy: Sendable {
    case none
    case panic
    case localRepair(maxEdits: Int)
}
