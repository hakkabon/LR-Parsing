import Foundation
import IncrementalParsing

/// Evidence produced by an incremental LR execution.
public struct LRIncrementalRuntimeResult: Sendable {
    public let result: LRRuntimeResult
    public let resumedAtToken: Int
    public let reusedFrameCount: Int
    public let reusedStateCount: Int
    public let reusedNodeCount: Int
    public let artifactIdentity: IncrementalArtifactIdentity
    public let evidence: IncrementalExecutionEvidence

    public init(
        result: LRRuntimeResult,
        resumedAtToken: Int,
        reusedFrameCount: Int,
        reusedStateCount: Int = 0,
        reusedNodeCount: Int = 0,
        artifactIdentity: IncrementalArtifactIdentity,
        evidence: IncrementalExecutionEvidence
    ) {
        self.result = result
        self.resumedAtToken = resumedAtToken
        self.reusedFrameCount = reusedFrameCount
        self.reusedStateCount = reusedStateCount
        self.reusedNodeCount = reusedNodeCount
        self.artifactIdentity = artifactIdentity
        self.evidence = evidence
    }

    /// Compatibility initializer for clients that constructed the Phase 6
    /// result directly. Runtime-produced values always carry exact identity.
    @available(*, deprecated, message: "Use runtime-produced results with exact artifact identity and evidence.")
    public init(
        result: LRRuntimeResult,
        resumedAtToken: Int,
        reusedFrameCount: Int
    ) {
        self.init(
            result: result,
            resumedAtToken: resumedAtToken,
            reusedFrameCount: reusedFrameCount,
            artifactIdentity: .init(
                id: "lr.runtime-table.unspecified",
                revision: 0,
                fingerprint: "unspecified"),
            evidence: .init(
                strategy: resumedAtToken > 0 ? .incremental : .full,
                measurements: [.init(
                    dimension: .init(rawValue: "lrTraceFrames"),
                    reused: reusedFrameCount,
                    rebuilt: max(0, result.frames.count - reusedFrameCount),
                    strategy: "prefix-replay")]))
    }
}

extension LRRuntimeTable {
    /// Exact, deterministic identity of a persisted runtime table. The framed
    /// representation is intentionally retained rather than process-randomized
    /// `Hashable` output, so identity is stable across executions.
    public var incrementalArtifactIdentity: IncrementalArtifactIdentity {
        .init(
            id: "lr.runtime-table",
            revision: 0,
            fingerprint: stableIncrementalFingerprint)
    }

    private var stableIncrementalFingerprint: String {
        func frame(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        func action(_ value: Action) -> String {
            switch value {
            case .shift(let state): return "shift:\(state)"
            case .reduce(let production): return "reduce:\(frame(production))"
            case .accept: return "accept"
            case .goTo(let state): return "goto:\(state)"
            }
        }
        let terminalPart = terminals.map(frame).joined()
        let productionPart = productions.map {
            frame($0.identity) + frame($0.lhs) + $0.rhs.map(frame).joined()
        }.joined(separator: "|")
        let cellPart = cells.map {
            "\($0.state):" + frame($0.symbol) + $0.actions.map(action).map(frame).joined()
        }.joined(separator: "|")
        return "lr-runtime-table-v1;T\(frame(terminalPart));P\(frame(productionPart));C\(frame(cellPart))"
    }
}

/// Owns the previous deterministic LR execution and resumes from the newest
/// checkpoint whose complete token prefix is unchanged.
///
/// Checkpoints contain the real LR state, symbol and syntax-node stacks. No
/// reductions are reconstructed by a client and no parser-external cache is
/// involved.
public final class LRIncrementalRuntime: @unchecked Sendable {
    private var previousTokens: [String] = []
    private var previousResult: LRRuntimeResult?
    private var previousTable: TableIdentity?
    private var previousWasForced = false

    public init() {}

    public func reset() {
        previousTokens = []
        previousResult = nil
        previousTable = nil
        previousWasForced = false
    }

    public func parse(
        _ tokens: [String],
        table: LRRuntimeTable,
        forcing forcedChoice: (state: Int, symbol: String, action: LRRuntimeTable.Action)? = nil,
        stepLimit: Int = 1_000,
        recovery: LRRuntimeRecovery = .disabled
    ) -> LRIncrementalRuntimeResult {
        let tableIdentity = TableIdentity(table)
        let artifactIdentity = table.incrementalArtifactIdentity
        var decision = reuseDecision(
            tableIdentity: tableIdentity,
            forcedChoice: forcedChoice)
        let knownTerminals = Set(table.terminals.filter { $0 != "$" })
        if decision.result != nil,
           recovery.maximumDiagnostics == 0,
           tokens.contains(where: { !knownTerminals.contains($0) }) {
            decision = .unavailable(.init(
                code: "lr.unknownTerminalPreflight",
                detail: "Unknown-terminal validation completes before the LR stack machine starts."))
        }
        let reusableResult = decision.result
        let commonPrefix = reusableResult == nil
            ? 0
            : zip(previousTokens, tokens).prefix { $0 == $1 }.count
        let candidate = reusableResult?.checkpoints
            .filter { $0.tokenIndex <= commonPrefix && $0.steps < stepLimit }
            .max { $0.tokenIndex < $1.tokenIndex }

        // Checkpoint zero represents a clean parse, not useful state reuse.
        let checkpoint = candidate.flatMap { $0.tokenIndex > 0 ? $0 : nil }
        let prefixFrames: [LRRuntimeFrame]
        if let checkpoint, let reusableResult {
            let newInput = tokens + ["$"]
            let oldInputCount = previousTokens.count + 1
            prefixFrames = reusableResult.frames.prefix(checkpoint.frameCount).map { frame in
                let consumed = max(0, oldInputCount - frame.remainingInput.count)
                return .init(
                    stack: frame.stack,
                    remainingInput: consumed <= newInput.count
                        ? Array(newInput.dropFirst(consumed)) : [],
                    action: frame.action,
                    state: frame.state,
                    symbol: frame.symbol,
                    productionIdentity: frame.productionIdentity)
            }
        } else {
            prefixFrames = []
        }

        let parsed = LRTableRuntime.parse(
            tokens,
            table: table,
            forcing: forcedChoice,
            stepLimit: stepLimit,
            recovery: recovery,
            resuming: checkpoint,
            prefixFrames: prefixFrames
        )
        let result: LRRuntimeResult
        if let checkpoint, let reusableResult {
            result = .init(
                tree: parsed.tree,
                frames: parsed.frames,
                outcome: parsed.outcome,
                diagnostics: parsed.diagnostics,
                checkpoints: reusableResult.checkpoints.filter {
                    $0.tokenIndex < checkpoint.tokenIndex
                } + parsed.checkpoints)
        } else {
            result = parsed
        }
        let evidence = executionEvidence(
            decision: decision,
            checkpoint: checkpoint,
            prefixFrames: prefixFrames,
            result: result)

        previousTokens = tokens
        previousResult = result
        previousTable = tableIdentity
        previousWasForced = forcedChoice != nil
        return .init(
            result: result,
            resumedAtToken: checkpoint?.tokenIndex ?? 0,
            reusedFrameCount: prefixFrames.count,
            reusedStateCount: checkpoint?.states.count ?? 0,
            reusedNodeCount: checkpoint?.nodes.count ?? 0,
            artifactIdentity: artifactIdentity,
            evidence: evidence
        )
    }

    private func reuseDecision(
        tableIdentity: TableIdentity,
        forcedChoice: (state: Int, symbol: String, action: LRRuntimeTable.Action)?
    ) -> ReuseDecision {
        guard let previousTable, let previousResult else { return .initial }
        guard previousTable == tableIdentity else {
            return .unavailable(.incompatibleArtifact)
        }
        guard forcedChoice == nil else {
            return .unavailable(.init(
                code: "lr.forcedChoice",
                detail: "A forced conflict choice requires execution from the initial state."))
        }
        guard !previousWasForced else {
            return .unavailable(.init(
                code: "lr.previousForcedChoice",
                detail: "State produced by a forced conflict choice is not a reusable deterministic baseline."))
        }
        guard previousResult.diagnostics.isEmpty,
              previousResult.outcome == .accepted else {
            return .unavailable(.invalidPreviousResult)
        }
        return .candidate(previousResult)
    }

    private func executionEvidence(
        decision: ReuseDecision,
        checkpoint: LRRuntimeCheckpoint?,
        prefixFrames: [LRRuntimeFrame],
        result: LRRuntimeResult
    ) -> IncrementalExecutionEvidence {
        let rebuiltFrames = max(0, result.frames.count - prefixFrames.count)
        let reusedStates = checkpoint?.states.count ?? 0
        let rebuiltStates = max(
            0, (result.checkpoints.last?.states.count ?? 0) - reusedStates)
        let measurements: [ReuseMeasurement] = [
            .init(
                dimension: .parserStates,
                reused: reusedStates,
                rebuilt: rebuiltStates,
                strategy: "resident-lr-stack-entries"),
            .init(
                dimension: .init(rawValue: "lrTraceFrames"),
                reused: prefixFrames.count,
                rebuilt: rebuiltFrames,
                strategy: "prefix-replay")
        ]
        if checkpoint != nil {
            return .init(strategy: .incremental, measurements: measurements)
        }
        switch decision {
        case .initial:
            return .init(strategy: .full, measurements: measurements)
        case .candidate:
            return .init(
                strategy: .fallback,
                fallback: .missingCheckpoint,
                measurements: measurements)
        case .unavailable(let reason):
            return .init(
                strategy: .fallback,
                fallback: reason,
                measurements: measurements)
        }
    }

    private enum ReuseDecision {
        case initial
        case candidate(LRRuntimeResult)
        case unavailable(IncrementalFallbackReason)

        var result: LRRuntimeResult? {
            if case .candidate(let result) = self { return result }
            return nil
        }
    }

    private struct TableIdentity: Hashable {
        let terminals: [String]
        let productions: [LRRuntimeTable.Production]
        let cells: [LRRuntimeTable.Cell]
        init(_ table: LRRuntimeTable) {
            terminals = table.terminals
            productions = table.productions
            cells = table.cells
        }
    }
}

public enum LRIncrementalParserError: Error, Equatable, Sendable {
    case transitionDoesNotProduceSnapshot
}

/// Shared-contract adapter around the native checkpoint runtime. Tokenization
/// remains caller-owned so the LR engine does not acquire a language policy.
public struct LRIncrementalParser: IncrementalParser, Sendable {
    public typealias Tokenizer = @Sendable (SourceSnapshot) throws -> [String]

    private let table: LRRuntimeTable
    private let tokenizer: Tokenizer
    private let stepLimit: Int
    private let recovery: LRRuntimeRecovery
    private var runtime = LRIncrementalRuntime()

    public init(
        table: LRRuntimeTable,
        stepLimit: Int = 1_000,
        recovery: LRRuntimeRecovery = .disabled,
        tokenizer: @escaping Tokenizer
    ) {
        self.table = table
        self.stepLimit = stepLimit
        self.recovery = recovery
        self.tokenizer = tokenizer
    }

    /// Convenience for token-oriented experiments whose terminals are
    /// separated by Unicode whitespace.
    public init(
        whitespaceSeparated table: LRRuntimeTable,
        stepLimit: Int = 1_000,
        recovery: LRRuntimeRecovery = .disabled
    ) {
        self.init(table: table, stepLimit: stepLimit, recovery: recovery) {
            $0.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
    }

    public mutating func parse(
        _ snapshot: SourceSnapshot,
        previous: LRIncrementalRuntimeResult?,
        change: SourceChange?
    ) throws -> LRIncrementalRuntimeResult {
        if let change, change.after != snapshot {
            throw LRIncrementalParserError.transitionDoesNotProduceSnapshot
        }
        // Reuse requires both the prior public result and its exact transition.
        // Withholding either is the shared contract's explicit full-parse path.
        if previous == nil || change == nil { runtime.reset() }
        return runtime.parse(
            try tokenizer(snapshot),
            table: table,
            stepLimit: stepLimit,
            recovery: recovery)
    }
}
