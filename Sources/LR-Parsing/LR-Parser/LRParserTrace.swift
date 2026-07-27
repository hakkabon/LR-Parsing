//
//  LRParserTrace.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/28.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Grammar

public struct LRTraceState: Hashable, CustomStringConvertible {
    public let index: Int
    public let identity: LRArtifactID

    public init(index: Int, identity: LRArtifactID) {
        self.index = index
        self.identity = identity
    }

    public var description: String { "state \(index) [\(identity)]" }
}

public struct LRTraceStackEntry: Hashable {
    public let state: LRTraceState
    public init(state: LRTraceState) { self.state = state }
}

public struct LRParserTraceEvent: CustomStringConvertible {
    public enum Kind: String, CaseIterable { case start, inspect, shift, reduce, accept, error, recovery }

    public let step: Int
    public let kind: Kind
    public let tokenIndex: Int
    public let lookahead: Terminal?
    public let state: LRTraceState
    public let targetState: LRTraceState?
    public let production: Production?
    public let productionIdentity: LRArtifactID?
    public let stack: [LRTraceStackEntry]
    public let message: String?

    public init(step: Int, kind: Kind, tokenIndex: Int, lookahead: Terminal?, state: LRTraceState, targetState: LRTraceState? = nil, production: Production? = nil, stack: [LRTraceStackEntry], message: String? = nil) {
        self.step = step
        self.kind = kind
        self.tokenIndex = tokenIndex
        self.lookahead = lookahead
        self.state = state
        self.targetState = targetState
        self.production = production
        self.productionIdentity = production?.lrArtifactID
        self.stack = stack
        self.message = message
    }

    public var description: String {
        var details = "[\(step)] \(kind.rawValue) @ token \(tokenIndex), state \(state.index)"
        if let lookahead { details += ", lookahead \(lookahead)" }
        if let targetState { details += " → state \(targetState.index)" }
        if let production { details += ", \(production)" }
        if let message { details += ": \(message)" }
        return details
    }
}
