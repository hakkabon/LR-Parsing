import Testing
import Parser
import IncrementalParsing
@testable import LR_Parsing

@Suite("Neutral LR table runtime")
struct LRTableRuntimeTests {
    private let table = LRRuntimeTable(
        terminals: ["a", "$"],
        productions: [.init(identity: "1", lhs: "S", rhs: ["a"])],
        cells: [
            .init(state: 0, symbol: "a", actions: [.shift(1)]),
            .init(state: 0, symbol: "S", actions: [.goTo(2)]),
            .init(state: 1, symbol: "$", actions: [.reduce("1")]),
            .init(state: 2, symbol: "$", actions: [.accept]),
        ]
    )

    @Test("executes persisted tables with trace and checkpoints")
    func accepts() {
        let result = LRTableRuntime.parse(["a"], table: table)
        #expect(result.outcome == .accepted)
        #expect(result.tree?.symbol == "S")
        #expect(result.frames.map(\.action) == ["shift ‘a’ to I1", "reduce S → a", "accept"])
        #expect(result.checkpoints.map(\.tokenIndex) == [0, 1])
    }

    @Test("reports unresolved cells and supports forced replay")
    func conflictReplay() {
        let conflicted = LRRuntimeTable(
            terminals: table.terminals, productions: table.productions,
            cells: [.init(state: 0, symbol: "a", actions: [.shift(1), .shift(2)])] + table.cells.dropFirst()
        )
        #expect(LRTableRuntime.parse(["a"], table: conflicted).outcome == .conflict(state: 0, symbol: "a"))
        let forced = LRTableRuntime.parse(["a"], table: conflicted, forcing: (0, "a", .shift(1)))
        #expect(forced.outcome == .accepted)
    }

    @Test("performs configured insertion recovery")
    func insertionRecovery() {
        let result = LRTableRuntime.parse([], table: table, recovery: .init(maximumDiagnostics: 1, preferredInsertions: ["a"]))
        #expect(result.outcome == .accepted)
        #expect(result.diagnostics.first?.recovery == .insertedToken)
        #expect(result.recoveryEdits == [.insert(symbol: "a", atToken: 0)])
        #expect(result.tree?.children.first?.isMissing == true)
    }

    @Test("persisted runtime recovery exports stable deletion evidence")
    func portableDeletionRecovery() throws {
        let result = LRTableRuntime.parse(
            ["x", "a"], table: table,
            recovery: .init(maximumDiagnostics: 1))
        #expect(result.outcome == .accepted)
        #expect(result.recoveryEdits == [.delete(symbol: "x", atToken: 0)])

        let plan = try result.incrementalRecoveryPlan(
            tokens: [
                ParseRecoveryTokenLocation(
                    tokenIndex: 0, id: "x#0", range: SourceRange(0, 1)),
                ParseRecoveryTokenLocation(
                    tokenIndex: 1, id: "a#1", range: SourceRange(2, 3)),
            ],
            endOfInputOffset: 3)

        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].action == .delete("x#0", range: SourceRange(0, 1)))
        #expect(plan.steps[0].expected == [.literal("a")])
        #expect(plan.steps[0].diagnosticID == "lr-runtime.diagnostic.0")
    }

    @Test("synchronization records the exact discarded token span")
    func portableSynchronizationRecovery() throws {
        let emptyTable = LRRuntimeTable(
            terminals: ["$"],
            productions: [],
            cells: [.init(state: 0, symbol: "$", actions: [.accept])])
        let result = LRTableRuntime.parse(
            ["x", "y"], table: emptyTable,
            recovery: .init(maximumDiagnostics: 1))

        #expect(result.outcome == .accepted)
        #expect(result.recoveryEdits == [
            .skip(symbols: ["x", "y"], fromToken: 0),
        ])
        let plan = try result.incrementalRecoveryPlan(
            tokens: [
                ParseRecoveryTokenLocation(
                    tokenIndex: 0, id: "x#0", range: SourceRange(0, 1)),
                ParseRecoveryTokenLocation(
                    tokenIndex: 1, id: "y#1", range: SourceRange(2, 3)),
            ],
            endOfInputOffset: 3)

        #expect(plan.totalCost == 2)
        #expect(plan.steps[0].action == .skip(
            ["x#0", "y#1"], range: SourceRange(0, 3)))
        #expect(plan.steps[0].diagnosticID == "lr-runtime.diagnostic.0")
    }
}
