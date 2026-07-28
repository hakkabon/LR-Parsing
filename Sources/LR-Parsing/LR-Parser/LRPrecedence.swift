import Grammar

public enum LRAssociativity: String, Hashable, CustomStringConvertible {
    case left
    case right
    case nonAssociative

    public var description: String { rawValue }
}

public struct LRPrecedence: Hashable, CustomStringConvertible {
    public let level: Int
    public let associativity: LRAssociativity

    public init(level: Int, associativity: LRAssociativity) {
        self.level = level
        self.associativity = associativity
    }

    public var description: String { "level \(level), \(associativity)" }
}

public struct LRPrecedenceLevel: Hashable {
    public let precedence: LRPrecedence
    public let terminals: Set<Terminal>

    public init(_ level: Int, associativity: LRAssociativity, terminals: Set<Terminal>) {
        self.precedence = LRPrecedence(level: level, associativity: associativity)
        self.terminals = terminals
    }
}

/// Declarative terminal precedence. A production inherits the declaration of
/// its rightmost declared terminal unless it has a `%prec`-style override.
public struct LRPrecedenceSpecification {
    public let levels: [LRPrecedenceLevel]
    public let productionOverrides: [Production: Terminal]
    private let terminalPrecedence: [Terminal: LRPrecedence]

    public init(levels: [LRPrecedenceLevel], productionOverrides: [Production: Terminal] = [:]) {
        precondition(Set(levels.map(\.precedence.level)).count == levels.count, "Precedence level numbers must be unique.")
        var values: [Terminal: LRPrecedence] = [:]
        for level in levels {
            for terminal in level.terminals {
                precondition(values[terminal] == nil, "A terminal may have only one precedence declaration.")
                values[terminal] = level.precedence
            }
        }
        self.levels = levels.sorted { $0.precedence.level < $1.precedence.level }
        self.productionOverrides = productionOverrides
        self.terminalPrecedence = values
    }

    public func precedence(of terminal: Terminal) -> LRPrecedence? { terminalPrecedence[terminal] }

    public func precedence(of production: Production) -> LRPrecedence? {
        if let terminal = productionOverrides[production] { return terminalPrecedence[terminal] }
        for symbol in production.rule.reversed() {
            if case .terminal(let terminal) = symbol, let value = terminalPrecedence[terminal] { return value }
        }
        return nil
    }
}
