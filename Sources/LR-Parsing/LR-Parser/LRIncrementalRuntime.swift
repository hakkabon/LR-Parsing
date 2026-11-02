import Foundation

/// Evidence produced by an incremental LR execution.
public struct LRIncrementalRuntimeResult: Sendable {
    public let result: LRRuntimeResult
    public let resumedAtToken: Int
    public let reusedFrameCount: Int

    public init(result: LRRuntimeResult, resumedAtToken: Int, reusedFrameCount: Int) {
        self.result = result
        self.resumedAtToken = resumedAtToken
        self.reusedFrameCount = reusedFrameCount
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

    public init() {}

    public func reset() {
        previousTokens = []
        previousResult = nil
        previousTable = nil
    }

    public func parse(
        _ tokens: [String],
        table: LRRuntimeTable,
        forcing forcedChoice: (state: Int, symbol: String, action: LRRuntimeTable.Action)? = nil,
        stepLimit: Int = 1_000,
        recovery: LRRuntimeRecovery = .disabled
    ) -> LRIncrementalRuntimeResult {
        let tableIdentity = TableIdentity(table)
        let reusableResult: LRRuntimeResult? = {
            guard previousTable == tableIdentity,
                  let previousResult,
                  previousResult.diagnostics.isEmpty,
                  previousResult.outcome == .accepted,
                  forcedChoice == nil else { return nil }
            return previousResult
        }()
        let commonPrefix = zip(previousTokens, tokens).prefix { $0 == $1 }.count
        let checkpoint = reusableResult?.checkpoints
            .filter { $0.tokenIndex <= commonPrefix }
            .max { $0.tokenIndex < $1.tokenIndex }
        let prefixFrames: [LRRuntimeFrame]
        if let checkpoint, let reusableResult {
            prefixFrames = Array(reusableResult.frames.prefix(checkpoint.frameCount))
        } else {
            prefixFrames = []
        }
        let result = LRTableRuntime.parse(
            tokens,
            table: table,
            forcing: forcedChoice,
            stepLimit: stepLimit,
            recovery: recovery,
            resuming: checkpoint,
            prefixFrames: prefixFrames
        )
        previousTokens = tokens
        previousResult = result
        previousTable = tableIdentity
        return .init(
            result: result,
            resumedAtToken: checkpoint?.tokenIndex ?? 0,
            reusedFrameCount: prefixFrames.count
        )
    }

    private struct TableIdentity: Hashable {
        let terminals: [String]
        let productions: [LRRuntimeTable.Production]
        let cells: [LRRuntimeTable.Cell]
        init(_ table: LRRuntimeTable) {
            terminals = table.terminals; productions = table.productions; cells = table.cells
        }
    }
}
