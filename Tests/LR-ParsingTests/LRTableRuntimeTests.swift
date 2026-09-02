import Testing
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
        #expect(result.tree?.children.first?.isMissing == true)
    }
}
