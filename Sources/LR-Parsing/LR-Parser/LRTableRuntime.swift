import Foundation

/// A serializable-client-friendly LR table. Consumers may execute persisted
/// tables without rebuilding a `Grammar` value or owning an LR stack machine.
public struct LRRuntimeTable: Sendable {
    public struct Production: Hashable, Sendable {
        public let identity: String
        public let lhs: String
        public let rhs: [String]
        public init(identity: String, lhs: String, rhs: [String]) {
            self.identity = identity; self.lhs = lhs; self.rhs = rhs
        }
    }
    public enum Action: Hashable, Sendable {
        case shift(Int), reduce(String), accept, goTo(Int)
    }
    public struct Cell: Hashable, Sendable {
        public let state: Int
        public let symbol: String
        public let actions: [Action]
        public init(state: Int, symbol: String, actions: [Action]) {
            self.state = state; self.symbol = symbol; self.actions = actions
        }
    }
    public let terminals: [String]
    public let productions: [Production]
    public let cells: [Cell]
    public init(terminals: [String], productions: [Production], cells: [Cell]) {
        self.terminals = terminals; self.productions = productions; self.cells = cells
    }
}

public struct LRRuntimeNode: Hashable, Sendable {
    public let symbol: String
    public let children: [LRRuntimeNode]
    public let productionIdentity: String?
    public let isMissing: Bool
    public init(symbol: String, children: [LRRuntimeNode], productionIdentity: String? = nil, isMissing: Bool = false) {
        self.symbol = symbol; self.children = children
        self.productionIdentity = productionIdentity; self.isMissing = isMissing
    }
}

public struct LRRuntimeFrame: Hashable, Sendable {
    public let stack: [String]
    public let remainingInput: [String]
    public let action: String
    public let state: Int
    public let symbol: String?
    public let productionIdentity: String?
    public init(stack: [String], remainingInput: [String], action: String, state: Int, symbol: String? = nil, productionIdentity: String? = nil) {
        self.stack = stack; self.remainingInput = remainingInput; self.action = action
        self.state = state; self.symbol = symbol; self.productionIdentity = productionIdentity
    }
}

public enum LRRuntimeRecoveryKind: String, Hashable, Codable, Sendable {
    case deletedToken, insertedToken, synchronized
}

public struct LRRuntimeDiagnostic: Hashable, Sendable {
    public let tokenIndex: Int
    public let state: Int
    public let unexpected: String
    public let expected: [String]
    public let message: String
    public let recovery: LRRuntimeRecoveryKind?
    public let recoverySymbol: String?
    public let recoveryDetail: String?
}

public struct LRRuntimeRecovery: Sendable {
    public let maximumDiagnostics: Int
    public let synchronizationTerminals: Set<String>
    public let preferredInsertions: [String]
    public init(maximumDiagnostics: Int, synchronizationTerminals: Set<String> = [], preferredInsertions: [String] = []) {
        self.maximumDiagnostics = maximumDiagnostics
        self.synchronizationTerminals = synchronizationTerminals
        self.preferredInsertions = preferredInsertions
    }
    public static let disabled = Self(maximumDiagnostics: 0)
}

public enum LRRuntimeOutcome: Hashable, Sendable {
    case accepted
    case rejected(message: String, expected: [String])
    case conflict(state: Int, symbol: String)
    case looping
}

public struct LRRuntimeCheckpoint: Hashable, Sendable {
    public let tokenIndex: Int
    public let steps: Int
    public let states: [Int]
    public let symbols: [String]
    public let nodes: [LRRuntimeNode]
    public let frameCount: Int
    public init(tokenIndex: Int, steps: Int, states: [Int], symbols: [String], nodes: [LRRuntimeNode], frameCount: Int) {
        self.tokenIndex = tokenIndex; self.steps = steps; self.states = states
        self.symbols = symbols; self.nodes = nodes; self.frameCount = frameCount
    }
}

public struct LRRuntimeResult: Sendable {
    public let tree: LRRuntimeNode?
    public let frames: [LRRuntimeFrame]
    public let outcome: LRRuntimeOutcome
    public let diagnostics: [LRRuntimeDiagnostic]
    public let checkpoints: [LRRuntimeCheckpoint]
}

/// Canonical deterministic execution for generated or persisted LR tables.
public enum LRTableRuntime {
    public static func parse(
        _ tokens: [String], table: LRRuntimeTable,
        forcing forcedChoice: (state: Int, symbol: String, action: LRRuntimeTable.Action)? = nil,
        stepLimit: Int = 1_000, recovery: LRRuntimeRecovery = .disabled,
        resuming checkpoint: LRRuntimeCheckpoint? = nil,
        prefixFrames: [LRRuntimeFrame] = []
    ) -> LRRuntimeResult {
        let eof = "$"
        let cells = Dictionary(uniqueKeysWithValues: table.cells.map { (Key($0.state, $0.symbol), $0.actions) })
        let productions = Dictionary(uniqueKeysWithValues: table.productions.map { ($0.identity, $0) })
        let terminals = Set(table.terminals.filter { $0 != eof })
        if recovery.maximumDiagnostics == 0, let unknown = tokens.first(where: { !terminals.contains($0) }) {
            return .init(tree: nil, frames: [], outcome: .rejected(message: "Unknown terminal ‘\(unknown)’.", expected: terminals.sorted()), diagnostics: [], checkpoints: [])
        }
        var input = tokens + [eof]
        var cursor = checkpoint?.tokenIndex ?? 0
        var states = checkpoint?.states ?? [0]
        var symbols = checkpoint?.symbols ?? []
        var nodes = checkpoint?.nodes ?? []
        var frames = checkpoint == nil ? [] : prefixFrames
        var checkpoints: [Int: LRRuntimeCheckpoint] = [:]
        if let checkpoint { checkpoints[checkpoint.tokenIndex] = checkpoint }
        else { checkpoints[0] = .init(tokenIndex: 0, steps: 0, states: states, symbols: symbols, nodes: nodes, frameCount: 0) }
        var diagnostics: [LRRuntimeDiagnostic] = []
        var inserted: Set<Int> = []
        var attempted: Set<String> = []
        var forcedUsed = false

        func actions(_ state: Int, _ symbol: String) -> [LRRuntimeTable.Action] { cells[Key(state, symbol)] ?? [] }
        func makeFrame(_ text: String, state: Int, symbol: String?, production: String? = nil) -> LRRuntimeFrame {
            var stack = ["I\(states[0])"]
            for i in symbols.indices { stack += [symbols[i], "I\(states[i + 1])"] }
            return .init(stack: stack, remainingInput: Array(input[cursor...]), action: text, state: state, symbol: symbol, productionIdentity: production)
        }
        func finish(_ outcome: LRRuntimeOutcome) -> LRRuntimeResult {
            .init(tree: outcome == .accepted ? nodes.last : nil, frames: frames, outcome: outcome,
                  diagnostics: diagnostics, checkpoints: checkpoints.values.sorted { $0.tokenIndex < $1.tokenIndex })
        }

        for step in (checkpoint?.steps ?? 0)..<stepLimit {
            guard let state = states.last else { return finish(.rejected(message: "Parser stack became empty.", expected: [])) }
            let lookahead = input[min(cursor, input.count - 1)]
            var candidates = actions(state, lookahead)
            if candidates.isEmpty {
                let expected = table.terminals.filter { !actions(state, $0).isEmpty }.sorted()
                frames.append(makeFrame("error: no action for ‘\(lookahead)’", state: state, symbol: lookahead))
                guard diagnostics.count < recovery.maximumDiagnostics else {
                    return finish(.rejected(message: "Unexpected ‘\(lookahead)’ in I\(state).", expected: expected))
                }
                let signature = "\(state):\(cursor):\(lookahead)"
                guard attempted.insert(signature).inserted else {
                    return finish(.rejected(message: "Recovery made no progress at ‘\(lookahead)’ in I\(state).", expected: expected))
                }
                let insertionOrder = recovery.preferredInsertions.filter(expected.contains) + expected.filter { !recovery.preferredInsertions.contains($0) }
                if let value = insertionOrder.first(where: { value in
                    guard value != eof, let action = actions(state, value).first else { return false }
                    if case .reduce = action { return true }
                    if case .shift(let target) = action { return !actions(target, lookahead).isEmpty }
                    return false
                }) {
                    inserted = Set(inserted.map { $0 >= cursor ? $0 + 1 : $0 }); inserted.insert(cursor); input.insert(value, at: cursor)
                    diagnostics.append(.init(tokenIndex: cursor, state: state, unexpected: lookahead, expected: expected, message: "Unexpected ‘\(lookahead)’ in I\(state).", recovery: .insertedToken, recoverySymbol: value, recoveryDetail: "Inserted missing ‘\(value)’ before ‘\(lookahead)’."))
                    frames.append(makeFrame("recover: insert missing ‘\(value)’", state: state, symbol: lookahead)); continue
                }
                if lookahead != eof, cursor + 1 < input.count, !actions(state, input[cursor + 1]).isEmpty {
                    let removed = input.remove(at: cursor)
                    inserted = Set(inserted.compactMap { $0 == cursor ? nil : ($0 > cursor ? $0 - 1 : $0) })
                    diagnostics.append(.init(tokenIndex: cursor, state: state, unexpected: removed, expected: expected, message: "Unexpected ‘\(removed)’ in I\(state).", recovery: .deletedToken, recoverySymbol: removed, recoveryDetail: "Deleted ‘\(removed)’ and resumed with ‘\(input[cursor])’."))
                    frames.append(makeFrame("recover: delete unexpected ‘\(removed)’", state: state, symbol: lookahead)); continue
                }
                if let value = insertionOrder.first(where: { value in
                    value != eof && actions(state, value).contains { if case .shift = $0 { true } else { false } }
                }) {
                    inserted = Set(inserted.map { $0 >= cursor ? $0 + 1 : $0 }); inserted.insert(cursor); input.insert(value, at: cursor)
                    diagnostics.append(.init(tokenIndex: cursor, state: state, unexpected: lookahead, expected: expected, message: "Unexpected ‘\(lookahead)’ in I\(state).", recovery: .insertedToken, recoverySymbol: value, recoveryDetail: "Inserted missing ‘\(value)’ before ‘\(lookahead)’."))
                    frames.append(makeFrame("recover: insert missing ‘\(value)’", state: state, symbol: lookahead)); continue
                }
                if let point = synchronizationPoint(input: input, cursor: cursor, states: states, cells: cells, preferred: recovery.synchronizationTerminals) {
                    let discarded = point.cursor - cursor
                    if point.pops > 0 { states.removeLast(point.pops); symbols.removeLast(min(point.pops, symbols.count)); nodes.removeLast(min(point.pops, nodes.count)) }
                    cursor = point.cursor
                    diagnostics.append(.init(tokenIndex: cursor, state: state, unexpected: lookahead, expected: expected, message: "Unexpected ‘\(lookahead)’ in I\(state).", recovery: .synchronized, recoverySymbol: input[cursor], recoveryDetail: "Discarded \(discarded) token(s), popped \(point.pops) state(s), and synchronized at ‘\(input[cursor])’."))
                    frames.append(makeFrame("recover: synchronize at ‘\(input[cursor])’", state: states.last ?? state, symbol: nil)); continue
                }
                return finish(.rejected(message: "Unexpected ‘\(lookahead)’ in I\(state); recovery failed.", expected: expected))
            }
            let action: LRRuntimeTable.Action
            if candidates.count > 1 {
                if let forcedChoice, forcedChoice.state == state, forcedChoice.symbol == lookahead,
                   candidates.contains(forcedChoice.action), !forcedUsed { action = forcedChoice.action; forcedUsed = true }
                else { frames.append(makeFrame("conflict", state: state, symbol: lookahead)); return finish(.conflict(state: state, symbol: lookahead)) }
            } else { action = candidates.removeFirst() }
            switch action {
            case .shift(let target):
                frames.append(makeFrame("shift ‘\(lookahead)’ to I\(target)", state: state, symbol: lookahead))
                symbols.append(lookahead); states.append(target)
                nodes.append(.init(symbol: inserted.contains(cursor) ? "⟨missing \(lookahead)⟩" : lookahead, children: [], isMissing: inserted.contains(cursor)))
                cursor += 1
                checkpoints[cursor] = .init(tokenIndex: cursor, steps: step + 1, states: states, symbols: symbols, nodes: nodes, frameCount: frames.count)
            case .reduce(let identity):
                guard let production = productions[identity], production.rhs.count <= symbols.count,
                      production.rhs.count < states.count, production.rhs.count <= nodes.count else {
                    return finish(.rejected(message: "Invalid reduction stack shape.", expected: []))
                }
                frames.append(makeFrame("reduce \(production.lhs) → \(production.rhs.isEmpty ? "ε" : production.rhs.joined(separator: " "))", state: state, symbol: lookahead, production: identity))
                let count = production.rhs.count; let children = count == 0 ? [] : Array(nodes.suffix(count))
                if count > 0 { symbols.removeLast(count); states.removeLast(count); nodes.removeLast(count) }
                guard let from = states.last, case .goTo(let target)? = actions(from, production.lhs).first else {
                    return finish(.rejected(message: "Missing goto for ‘\(production.lhs)’ after reduction.", expected: []))
                }
                symbols.append(production.lhs); states.append(target)
                nodes.append(.init(symbol: production.lhs, children: children, productionIdentity: identity))
            case .accept:
                frames.append(makeFrame("accept", state: state, symbol: lookahead)); return finish(.accepted)
            case .goTo:
                return finish(.rejected(message: "Invalid goto action on terminal.", expected: []))
            }
        }
        return finish(.looping)
    }

    private struct Key: Hashable { let state: Int; let symbol: String; init(_ state: Int, _ symbol: String) { self.state = state; self.symbol = symbol } }
    private static func synchronizationPoint(input: [String], cursor: Int, states: [Int], cells: [Key: [LRRuntimeTable.Action]], preferred: Set<String>) -> (cursor: Int, pops: Int)? {
        for inputIndex in cursor..<input.count {
            if !preferred.isEmpty, input[inputIndex] != "$", !preferred.contains(input[inputIndex]) { continue }
            for stackIndex in states.indices.reversed() where !(cells[Key(states[stackIndex], input[inputIndex])] ?? []).isEmpty {
                let pops = states.count - stackIndex - 1
                if inputIndex > cursor || pops > 0 { return (inputIndex, pops) }
            }
        }
        return nil
    }
}
