//
//  LRParser.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Lexer
import OSLog

enum LRParseError: Error, CustomStringConvertible {
    case generationFailed(String)
    case tokenError(String)
    case unexpectedToken(token: String, state: Int)
    case unexpectedEOF(state: Int)
    case internalError(String)
    
    var description: String {
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
    
    
    public enum Algorithm {
        case lr0, slr, lr1, lalr
    }

    let generator: LRTableGenerator
    let symbols = ["|", "\\", "^", ":", ",", "$", ".", "\"", "¶", ">", "#", "+", "-", "{","[", "<", "(",
                   "'", "}", "]", ":]", ")", ";", "/", "*", "?", "??", ":="]

    public init(grammar: Grammar, algorithm: Algorithm) {
        self.generator = LRTableGenerator(grammar: grammar, algorithm: algorithm)
    }
    
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
        guard let (table, statesDebug) = generator.generate() else {
            throw LRParseError.generationFailed("Grammar contains conflicts (not LR-compliant).")
        }

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
            guard let action = table.action[currentStateId]?[terminal] else {
                if case .meta(.eof) = terminal {
                    throw LRParseError.unexpectedEOF(state: currentStateId)
                } else {
                    print("Syntax Error: Unexpected token \(terminal) in state \(currentStateId)")
                    print("State Items: \(statesDebug[currentStateId]!)")
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
