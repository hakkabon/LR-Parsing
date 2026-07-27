import Grammar

/// A deterministic semantic identifier. Unlike Swift `Hashable` values, its
/// representation is stable across processes and repeated generation.
public struct LRArtifactID: RawRepresentable, Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Symbol {
    var lrStableKey: String {
        switch self {
        case .terminal(let terminal): "terminal(\(terminal.lrStableKey))"
        case .nonTerminal(let nonterminal): "nonterminal(\(lrFrame(nonterminal.name)))"
        case .metaSymbol(let symbol): "meta(\(lrFrame(symbol.rawValue)))"
        }
    }
}

extension Terminal {
    var lrStableKey: String {
        switch self {
        case .string(let value): "string:\(lrFrame(value))"
        case .stringList(let values): "list:" + values.map(lrFrame).joined()
        case .characterRange(let range): "range:\(lrFrame(String(range.lowerBound)))\(lrFrame(String(range.upperBound)))"
        case .regularExpression(let expression): "regex:\(lrFrame(expression.pattern))"
        case .meta(let value): "meta:\(lrFrame(value.rawValue))"
        }
    }
}

private func lrFrame(_ value: String) -> String { "\(value.utf8.count):\(value)" }

extension Production {
    public var lrArtifactID: LRArtifactID {
        LRArtifactID(rawValue: "production:\(lrFrame(goal.name))->\(rule.map { lrFrame($0.lrStableKey) }.joined())")
    }
}

public struct LRProductionArtifact: Hashable {
    public let identity: LRArtifactID
    public let production: Production

    public init(production: Production) {
        self.production = production
        self.identity = production.lrArtifactID
    }
}

extension LRAction {
    var lrStableKey: String {
        switch self {
        case .shift(let target): "shift:\(target)"
        case .reduce(let production): "reduce:\(production.lrArtifactID.rawValue)"
        case .accept: "accept"
        }
    }
}

extension LRItem {
    public var identity: LRArtifactID {
        let lookaheadKey = lookahead.map(\.lrStableKey).sorted().joined(separator: ",")
        return LRArtifactID(rawValue: "item:\(production.lrArtifactID.rawValue)@\(dotIndex)[\(lookaheadKey)]")
    }
}
