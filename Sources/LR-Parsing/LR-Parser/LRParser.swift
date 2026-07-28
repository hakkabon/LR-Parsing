//
//  LRParser.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser
import Lexer
import OSLog

public enum LRParseError: Error, CustomStringConvertible {
    case generationFailed(String)
    case tokenError(String)
    case unexpectedToken(token: String, state: Int)
    case unexpectedEOF(state: Int)
    case internalError(String)
    
    public var description: String {
        switch self {
        case .generationFailed(let msg): return "Parser Generator Failed: \(msg)"
        case .tokenError(let msg): return "Could not extract terminal from token: \(msg)"
        case .unexpectedToken(let t, let s): return "Syntax Error: Unexpected token '\(t)' at state \(s)."
        case .unexpectedEOF(let s): return "Syntax Error: Unexpected End of File at state \(s)."
        case .internalError(let msg): return "Internal Parser Error: \(msg)"
        }
    }
}

public class LRParser: Parser {
    
    
    public enum Algorithm: String, CaseIterable, Sendable {
        case lr0, slr, lr1, lalr
    }

    let generator: LRTableGenerator
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "+", "-", "{","[", "<", "(",
                   "'", "}", "]", ":]", ")", ";", "/", "*", "?", "??", ":=", "="]

    public init(grammar: Grammar, algorithm: Algorithm, precedence: LRPrecedenceSpecification? = nil) {
        self.generator = LRTableGenerator(grammar: grammar, algorithm: algorithm, precedence: precedence)
    }

    /// Generates an inspectable automaton even when the grammar has conflicts.
    public func generate() -> LRAutomaton { generator.generate() }
    
    struct StackElement {
        let state: Int
        let node: ParseTree
    }

    public func syntaxTree(for string: String) throws -> ParseTree {
        return try parse(string)
    }

    /// Parses `source` text using GrammarTokenizer's general-purpose
    /// `Tokenizer` (configured with this parser's fixed `symbols` list), then
    /// runs the shift/reduce loop.
    public func parse(_ source: String) throws -> ParseTree {
        try parse(stream: TokenizerStream(source: source, symbols: Set(symbols), keywords: []))
    }

    /// Parses with structured diagnostics and optional deterministic recovery.
    /// Local repair tries a bounded single-token deletion or insertion first;
    /// panic mode discards input until the current state has a valid action.
    public func parseOutcome(_ source: String, recovery: RecoveryPolicy = .none, tracing: Bool = false) throws -> ParserOutcome {
        let stream = TokenizerStream(source: source, symbols: Set(symbols), keywords: [])
        var tokens: [(Terminal, Range<String.Index>?)] = []
        for index in 0..<stream.count { tokens.append(try stream.terminal(at: index)) }
        tokens.append((.meta(.eof), nil))

        let automaton = generate()
        guard automaton.unresolvedConflicts.isEmpty else {
            return ParserOutcome(status: .rejected, tree: nil, diagnostics: [
                ParserDiagnostic(severity: .error, message: "Grammar has \(automaton.unresolvedConflicts.count) unresolved LR conflict(s).")
            ], recoveryEdits: [])
        }
        let table = LRTable(action: automaton.actionTable, gotoTable: automaton.gotoTable)
        var stack = [StackElement(state: 0, node: .empty)]
        var position = 0
        var diagnostics: [ParserDiagnostic] = []
        var edits: [RecoveryEdit] = []
        var trace: [LRParserTraceEvent] = []

        func stateReference(_ index: Int) -> LRTraceState {
            LRTraceState(index: index, identity: automaton.state(index)?.identity ?? LRArtifactID(rawValue: "state-index:\(index)"))
        }
        func snapshot() -> [LRTraceStackEntry] { stack.map { LRTraceStackEntry(state: stateReference($0.state)) } }
        func record(_ kind: LRParserTraceEvent.Kind, tokenIndex: Int, lookahead: Terminal?, state: Int, target: Int? = nil, production: Production? = nil, message: String? = nil) {
            guard tracing else { return }
            trace.append(LRParserTraceEvent(step: trace.count, kind: kind, tokenIndex: tokenIndex, lookahead: lookahead, state: stateReference(state), targetState: target.map(stateReference), production: production, stack: snapshot(), message: message))
        }
        record(.start, tokenIndex: 0, lookahead: tokens[0].0, state: 0)

        while true {
            guard let state = stack.last?.state else { throw LRParseError.internalError("Stack underflow.") }
            let terminal = tokens[position].0
            var action = table.action(for: terminal, in: state)
            var insertedThisStep = false
            record(.inspect, tokenIndex: position, lookahead: terminal, state: state)

            if action == nil {
                let expected = Set(table.action[state]?.keys ?? Dictionary<Terminal, LRAction>().keys)
                diagnostics.append(ParserDiagnostic(severity: .error, message: "Unexpected token \(terminal).", state: state, expected: expected))
                record(.error, tokenIndex: position, lookahead: terminal, state: state, message: "unexpected token")
                switch recovery {
                case .none:
                    return ParserOutcome(status: .rejected, tree: nil, diagnostics: diagnostics, recoveryEdits: edits, trace: trace)
                case .localRepair(let maximum) where edits.count < maximum:
                    if position + 1 < tokens.count, table.action(for: tokens[position + 1].0, in: state) != nil {
                        edits.append(.delete(terminal: terminal, atToken: position))
                        record(.recovery, tokenIndex: position, lookahead: terminal, state: state, message: edits.last?.description)
                        position += 1
                        continue
                    }
                    if let insertion = table.action[state]?.first(where: { if case .shift = $0.value { return true }; return false }) {
                        edits.append(.insert(terminal: insertion.key, atToken: position))
                        record(.recovery, tokenIndex: position, lookahead: terminal, state: state, message: edits.last?.description)
                        action = insertion.value
                        insertedThisStep = true
                    } else {
                        fallthrough
                    }
                case .localRepair:
                    fallthrough
                case .panic:
                    let start = position
                    var skipped: [Terminal] = []
                    while position < tokens.count - 1, table.action(for: tokens[position].0, in: state) == nil {
                        skipped.append(tokens[position].0)
                        position += 1
                    }
                    guard !skipped.isEmpty, table.action(for: tokens[position].0, in: state) != nil else {
                        return ParserOutcome(status: .rejected, tree: nil, diagnostics: diagnostics, recoveryEdits: edits, trace: trace)
                    }
                    edits.append(.skip(terminals: skipped, fromToken: start))
                    record(.recovery, tokenIndex: start, lookahead: terminal, state: state, message: edits.last?.description)
                    continue
                }
            }

            guard let selected = action else { continue }
            switch selected {
            case .shift(let nextState):
                let node = insertedThisStep ? ParseTree.empty : (tokens[position].1.map(ParseTree.leaf) ?? .empty)
                stack.append(StackElement(state: nextState, node: node))
                record(.shift, tokenIndex: position, lookahead: insertedThisStep ? nil : terminal, state: state, target: nextState)
                if !insertedThisStep { position += 1 }
            case .reduce(let production):
                let count = production.rule.count
                guard stack.count >= count + 1 else { throw LRParseError.internalError("Stack not deep enough for reduction.") }
                let children = count == 0 ? [] : stack.suffix(count).map(\.node)
                if count > 0 { stack.removeLast(count) }
                guard let back = stack.last?.state, let next = table.gotoTable[back]?[production.goal] else {
                    throw LRParseError.internalError("Missing GOTO after reduction.")
                }
                stack.append(StackElement(state: next, node: .node(production.goal, children: children)))
                record(.reduce, tokenIndex: position, lookahead: terminal, state: state, target: next, production: production)
            case .accept:
                record(.accept, tokenIndex: position, lookahead: terminal, state: state)
                return ParserOutcome(status: edits.isEmpty ? .accepted : .recovered, tree: stack.last?.node, diagnostics: diagnostics, recoveryEdits: edits, trace: trace)
            }
        }
    }

    /// Runs the shift/reduce loop against any `TokenStream` — the DFA-driven
    /// `LexerTokenStream` (built via a `LexerBuilder` bootstrapped from a
    /// `GrammarVocabulary`) and the hand-written `TokenizerStream` are both
    /// accepted interchangeably, as is any other conformance.
    ///
    /// - Parameter stream: A positioned sequence of tokens, each resolvable
    ///   to a `Terminal` and a source `Range<String.Index>`.
    public func parse<S: TokenStream>(stream: S) throws -> ParseTree {
        // Generate Tables
        // In a real scenario, you might generate these once in 'init' and throw there,
        // but checking here ensures safety.
        let automaton = generator.generate()
        guard automaton.unresolvedConflicts.isEmpty else {
            throw LRParseError.generationFailed("Grammar contains unresolved conflicts (not LR-compliant).")
        }
        let table = LRTable(action: automaton.actionTable, gotoTable: automaton.gotoTable)

        var cursor = StreamCursor(stream: stream)

        // Initialize Stack
        // We use .empty as the sentinel for State 0
        var stack: [StackElement] = [StackElement(state: 0, node: .empty)]

        var current = try cursor.peek()

        while true {
            guard let currentStateId = stack.last?.state else {
                throw LRParseError.internalError("Stack underflow (empty stack).")
            }
            
            let terminal = current.terminal
            
            // Look up Action
            guard let action = table.action(for: terminal, in: currentStateId) else {
                if case .meta(.eof) = terminal {
                    throw LRParseError.unexpectedEOF(state: currentStateId)
                } else {
                    throw LRParseError.unexpectedToken(token: "\(terminal)", state: currentStateId)
                }
            }
            
            switch action {
            case .shift(let nextState):
                // Create a Leaf Node
                let leafNode: SyntaxTree<NonTerminal, Range<String.Index>> = current.range.map(ParseTree.leaf) ?? .empty

                stack.append(StackElement(state: nextState, node: leafNode))
                cursor.advance()
                current = try cursor.peek()
                
            case .reduce(let production):
                let childCount = production.rule.count
                var children: [ParseTree] = []
                
                // Validate Stack Depth
                // We need childCount items + 1 (the current state) available
                if stack.count < childCount + 1 {
                    throw LRParseError.internalError("Stack not deep enough for reduction: \(production)")
                }
                
                // Pop children
                if childCount > 0 {
                    let suffix = stack.suffix(childCount)
                    children = suffix.map { $0.node }
                    stack.removeLast(childCount)
                }
                
                // Determine GOTO
                guard let backState = stack.last?.state else {
                    throw LRParseError.internalError("Lost state context after reduce.")
                }
                
                guard let nextState = table.gotoTable[backState]? [production.goal] else {
                    throw LRParseError.internalError("Missing GOTO entry for state \(backState) -> \(production.goal).")
                }
                
                // Create NonTerminal Node
                let newNode = ParseTree.node(production.goal, children: children)
                stack.append(StackElement(state: nextState, node: newNode))
                
            case .accept:
                // The stack should contain: [Bottom(.empty), Result(Node)]
                guard let resultNode = stack.last?.node else {
                    throw LRParseError.internalError("Accepted state reached but no tree node found.")
                }
                
                // Validation: Ensure it's not the .empty marker
                if case .empty = resultNode {
                    throw LRParseError.internalError("Accepted an empty parse tree.")
                }
                
                return resultNode
            }
        }
    }
}

/// A one-token-lookahead cursor over a `TokenStream`, used by the shift/reduce
/// loop above in place of calling `next()` directly on a GrammarTokenizer
/// `Tokenizer`.
///
/// LR parsing only ever reads the input strictly left-to-right, one token of
/// lookahead at a time, so a `TokenStream`'s random-access `terminal(at:)` is
/// used here purely as an indexed pull — `peek()`/`advance()` never revisit a
/// past position.
///
/// Once the stream is exhausted (`position >= stream.count`), or a
/// `Terminal.meta(.eof)` is encountered before that point (some
/// `TokenStream` front ends include an explicit end-of-input entry, others
/// don't — see `Lexer`'s `TokenizerStream`), `peek()` keeps returning
/// `Terminal.meta(.eof)` with a `nil` range indefinitely — mirroring the
/// `Token? == nil` sentinel the previous `Tokenizer.next()`-based loop relied on.
private struct StreamCursor<S: TokenStream> {
    let stream: S
    private(set) var position = 0

    init(stream: S) { self.stream = stream }

    func peek() throws -> (terminal: Terminal, range: Range<String.Index>?) {
        guard position < stream.count else { return (.meta(.eof), nil) }
        let (terminal, range) = try stream.terminal(at: position)
        if case .meta(.eof) = terminal { return (.meta(.eof), nil) }
        return (terminal, range)
    }

    mutating func advance() {
        if position < stream.count { position += 1 }
    }
}
