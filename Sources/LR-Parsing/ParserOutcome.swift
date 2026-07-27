//
//  ParserOutcome.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/28.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser

public enum ParserOutcomeStatus: String, Sendable {
    case accepted
    case recovered
    case rejected
}

public struct ParserDiagnostic: CustomStringConvertible {
    public enum Severity: String, Sendable { case warning, error }
    public let severity: Severity
    public let message: String
    public let state: Int?
    public let expected: Set<Terminal>

    public init(severity: Severity, message: String, state: Int? = nil, expected: Set<Terminal> = []) {
        self.severity = severity
        self.message = message
        self.state = state
        self.expected = expected
    }

    public var description: String { "\(severity.rawValue): \(message)" }
}

public enum RecoveryEdit: CustomStringConvertible {
    case insert(terminal: Terminal, atToken: Int)
    case delete(terminal: Terminal, atToken: Int)
    case skip(terminals: [Terminal], fromToken: Int)

    public var description: String {
        switch self {
        case .insert(let terminal, let index): return "insert \(terminal) at token \(index)"
        case .delete(let terminal, let index): return "delete \(terminal) at token \(index)"
        case .skip(let terminals, let index): return "skip \(terminals.map(\.description).joined(separator: " ")) from token \(index)"
        }
    }
}

public struct ParserOutcome {
    public let status: ParserOutcomeStatus
    public let tree: ParseTree?
    public let diagnostics: [ParserDiagnostic]
    public let recoveryEdits: [RecoveryEdit]
    public let trace: [LRParserTraceEvent]

    public init(status: ParserOutcomeStatus, tree: ParseTree?, diagnostics: [ParserDiagnostic], recoveryEdits: [RecoveryEdit], trace: [LRParserTraceEvent] = []) {
        self.status = status
        self.tree = tree
        self.diagnostics = diagnostics
        self.recoveryEdits = recoveryEdits
        self.trace = trace
    }
}

public enum RecoveryPolicy: Sendable {
    case none
    case panic
    case localRepair(maxEdits: Int)
}
