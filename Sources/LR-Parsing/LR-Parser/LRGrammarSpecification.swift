import Grammar

/// Engine-neutral input for clients that own their grammar document model.
public struct LRGrammarRuleSpecification: Hashable, Sendable {
    public let lhs: String
    public let rhs: [String]
    public init(lhs: String, rhs: [String]) { self.lhs = lhs; self.rhs = rhs }
}

public struct LRGrammarPrecedenceSpecification: Hashable, Sendable {
    public let level: Int
    public let associativity: LRAssociativity
    public let terminals: [String]
    public init(level: Int, associativity: LRAssociativity, terminals: [String]) {
        self.level = level; self.associativity = associativity; self.terminals = terminals
    }
}

public struct LRGrammarSpecification: Hashable, Sendable {
    public let start: String
    public let terminals: [String]
    public let rules: [LRGrammarRuleSpecification]
    public let precedence: [LRGrammarPrecedenceSpecification]

    public init(start: String, terminals: [String], rules: [LRGrammarRuleSpecification], precedence: [LRGrammarPrecedenceSpecification] = []) {
        self.start = start; self.terminals = terminals; self.rules = rules; self.precedence = precedence
    }
}

public extension LRParser {
    convenience init(specification: LRGrammarSpecification, algorithm: Algorithm) {
        let terminals = Set(specification.terminals)
        let productions = specification.rules.map { rule in
            Production(goal: NonTerminal(name: rule.lhs), rule: rule.rhs.map { symbol in
                terminals.contains(symbol) ? .terminal(Terminal(string: symbol)) : .nonTerminal(NonTerminal(name: symbol))
            })
        }
        let grammar = Grammar(productions: productions, start: NonTerminal(name: specification.start), lexicalTokens: [:])
        let precedence = specification.precedence.isEmpty ? nil : LRPrecedenceSpecification(levels: specification.precedence.map {
            LRPrecedenceLevel($0.level, associativity: $0.associativity, terminals: Set($0.terminals.map(Terminal.init(string:))))
        })
        self.init(grammar: grammar, algorithm: algorithm, precedence: precedence)
    }
}

public extension Terminal {
    var lrDisplayName: String { self == .meta(.eof) ? "$" : description }
    /// The unquoted symbol key used by neutral tables and token streams.
    var lrSymbolName: String {
        switch self {
        case .string(let value): value
        case .meta(.eof): "$"
        default: description
        }
    }
}

public extension Symbol {
    var lrDisplayName: String {
        switch self {
        case .terminal(let terminal): terminal.lrDisplayName
        case .nonTerminal(let nonterminal): nonterminal.name
        case .metaSymbol(let symbol): symbol.rawValue
        }
    }

    var lrSymbolName: String {
        switch self {
        case .terminal(let terminal): terminal.lrSymbolName
        case .nonTerminal(let nonterminal): nonterminal.name
        case .metaSymbol(let symbol): symbol.rawValue
        }
    }
}
