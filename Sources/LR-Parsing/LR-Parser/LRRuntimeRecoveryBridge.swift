import Grammar
import IncrementalParsing
import Parser

public extension LRRuntimeResult {
    /// Exports persisted-table repairs using the same source-coordinate,
    /// stable-token recovery plan as grammar-backed LL and LR parsers.
    func incrementalRecoveryPlan<TokenID: Hashable & Sendable>(
        tokens: [ParseRecoveryTokenLocation<TokenID>],
        endOfInputOffset: Int,
        maximumCost: Int? = nil
    ) throws -> RecoveryPlan<GrammarNormalizedTerminal, TokenID> {
        var steps: [RecoveryStep<GrammarNormalizedTerminal, TokenID>] = []
        var diagnosticCursor = diagnostics.startIndex
        for edit in recoveryEdits {
            let portable: ParseRecoveryEdit
            let cost: Int
            let recoveryKind: LRRuntimeRecoveryKind
            switch edit {
            case .insert(let symbol, let tokenIndex):
                portable = .insert(terminal: .literal(symbol), atToken: tokenIndex)
                cost = 1
                recoveryKind = .insertedToken
            case .delete(let symbol, let tokenIndex):
                portable = .delete(terminal: .literal(symbol), atToken: tokenIndex)
                cost = 1
                recoveryKind = .deletedToken
            case .skip(let symbols, let tokenIndex):
                portable = .skip(
                    terminals: symbols.map(GrammarNormalizedTerminal.literal),
                    fromToken: tokenIndex)
                cost = max(1, symbols.count)
                recoveryKind = .synchronized
            }
            let action = try portable.incrementalAction(
                tokens: tokens, endOfInputOffset: endOfInputOffset)
            let diagnosticIndex = diagnostics.indices[diagnosticCursor...].first {
                diagnostics[$0].recovery == recoveryKind
            }
            if let diagnosticIndex {
                diagnosticCursor = diagnostics.index(after: diagnosticIndex)
            }
            let expected = diagnosticIndex.map {
                Set(diagnostics[$0].expected.map(GrammarNormalizedTerminal.literal))
            } ?? []
            steps.append(.init(
                action: action,
                expected: expected,
                cost: cost,
                diagnosticID: diagnosticIndex.map { "lr-runtime.diagnostic.\($0)" }))
        }
        let totalCost = steps.reduce(0) { $0 + $1.cost }
        return try RecoveryPlan(
            steps: steps,
            maximumCost: maximumCost ?? totalCost)
    }
}
