//
//  LRParser.swift
//  LR-Parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/11/30.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Tokenizer
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
    
    public func parse(_ source: String) throws -> ParseTree {
        // Generate Tables
        // In a real scenario, you might generate these once in 'init' and throw there,
        // but checking here ensures safety.
        guard let (table, statesDebug) = generator.generate() else {
            throw LRParseError.generationFailed("Grammar contains conflicts (not LR-compliant).")
        }
        
        // Setup Tokenizer & Constants
        let eofTerminal = Terminal.meta(.eof)
        // Ensure your Tokenizer and Symbol mapping matches your specific implementation
        let tokenizer = Tokenizer(source, symbols: Set(symbols), keywords: [])
        
        // Initialize Stack
        // We use .empty as the sentinel for State 0
        var stack: [StackElement] = [StackElement(state: 0, node: .empty)]
        
        var currentToken = tokenizer.next()
        
        // Helper: Convert Token? -> Terminal
        func getTerminal(_ t: Token?) -> Terminal {
            guard let t = t else { return eofTerminal }
            switch t.type {
            case .symbol(let s): return Terminal(string: s)
            case .literal(let s): return Terminal(string: s)
            case .identifier(let s): return Terminal(string: s)
            default: return Terminal(string: t.description)
            }
        }
        
        while true {
            guard let currentStateId = stack.last?.state else {
                throw LRParseError.internalError("Stack underflow (empty stack).")
            }
            
            let terminal = getTerminal(currentToken)
            
            // Look up Action
            guard let action = table.action[currentStateId]?[terminal] else {
                if currentToken == nil {
                    throw LRParseError.unexpectedEOF(state: currentStateId)
                } else {
                    print("Syntax Error: Unexpected token \(terminal) in state \(currentStateId)")
                    print("State Items: \(statesDebug[currentStateId]!)")
                    throw LRParseError.unexpectedToken(token: currentToken!.description, state: currentStateId)
                }
            }
            
            switch action {
            case .shift(let nextState):
                // Create a Leaf Node
                let leafNode: SyntaxTree<NonTerminal, Range<String.Index>>
                if let token = currentToken {
                    leafNode = .leaf(token.range)
                } else {
                    // It's rare to shift EOF, but if the grammar allows it:
                    leafNode = .empty
                }
                
                stack.append(StackElement(state: nextState, node: leafNode))
                currentToken = tokenizer.next()
                
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

    /// Extracts the `Terminal` type contained in a given token.
    func extractTerminal(_ token: Token) throws -> (terminal: Terminal, range: Range<String.Index>) {
        let (terminal, range) = switch token.type {
        case .symbol(let symbol):
            (Terminal(string: symbol), token.range)
        case .literal(let literal):
            (Terminal(string: literal), token.range)
        case .identifier(let identifier):
            (Terminal(string: identifier), token.range)
        case .number(let number):
            switch number {
            case .decimal(let value), .binary(let value), .octal(let value), .hexadecimal(let value):
                (Terminal(string: "\(value)"), token.range)
            }
        case .eof:
            (Terminal.meta(.eof), token.range)
        default:
            throw LRParseError.tokenError("symbol \(token) not recognized")
        }
        return (terminal, range)
    }
}
