import XCTest
import IncrementalParsing
@testable import LR_Parsing

final class LRIncrementalRuntimeTests: XCTestCase {
    func testResumesFromLastUnchangedPrefixCheckpointWithSharedEvidence() {
        let session = LRIncrementalRuntime()
        let initial = session.parse(["a", "b"], table: alternativeSuffixTable)
        XCTAssertEqual(initial.result.outcome, .accepted)
        XCTAssertEqual(initial.evidence.strategy, .full)

        let edited = session.parse(["a", "c"], table: alternativeSuffixTable)
        XCTAssertEqual(edited.resumedAtToken, 1)
        XCTAssertGreaterThan(edited.reusedFrameCount, 0)
        XCTAssertGreaterThan(edited.reusedStateCount, 0)
        XCTAssertGreaterThan(edited.reusedNodeCount, 0)
        XCTAssertEqual(edited.evidence.strategy, .incremental)
        XCTAssertEqual(
            edited.evidence.measurements.first { $0.dimension == .parserStates }?.reused,
            edited.reusedStateCount)
        XCTAssertEqual(edited.result.outcome, .accepted)
    }

    func testResumedExecutionPreservesNativeRecoveryScript() {
        let session = LRIncrementalRuntime()
        _ = session.parse(
            ["a", "b"], table: alternativeSuffixTable,
            recovery: .init(maximumDiagnostics: 1))

        let edited = session.parse(
            ["a", "x", "b"], table: alternativeSuffixTable,
            recovery: .init(maximumDiagnostics: 1))

        XCTAssertEqual(edited.resumedAtToken, 1)
        XCTAssertEqual(edited.result.outcome, .accepted)
        XCTAssertEqual(edited.result.recoveryEdits, [
            .delete(symbol: "x", atToken: 1),
        ])
    }

    func testReportsWhyNativeReuseIsUnavailable() {
        let session = LRIncrementalRuntime()
        _ = session.parse(["a", "b"], table: alternativeSuffixTable)

        let changedTable = LRRuntimeTable(
            terminals: alternativeSuffixTable.terminals + ["d"],
            productions: alternativeSuffixTable.productions,
            cells: alternativeSuffixTable.cells)
        let incompatible = session.parse(["a", "b"], table: changedTable)
        XCTAssertEqual(incompatible.evidence.strategy, .fallback)
        XCTAssertEqual(incompatible.evidence.fallback?.code, "incompatibleArtifact")
        XCTAssertEqual(incompatible.resumedAtToken, 0)

        _ = session.parse(["a", "x"], table: alternativeSuffixTable)
        let afterRejection = session.parse(["a", "b"], table: alternativeSuffixTable)
        XCTAssertEqual(afterRejection.evidence.strategy, .fallback)
        XCTAssertEqual(afterRejection.evidence.fallback?.code, "invalidPreviousResult")
    }

    func testForcedExecutionNeverBecomesOrdinaryReuseBaseline() {
        let session = LRIncrementalRuntime()
        let forced = session.parse(
            ["a", "b"],
            table: alternativeSuffixTable,
            forcing: (state: 0, symbol: "a", action: .shift(1)))
        XCTAssertEqual(forced.result.outcome, .accepted)

        let ordinary = session.parse(["a", "c"], table: alternativeSuffixTable)
        XCTAssertEqual(ordinary.resumedAtToken, 0)
        XCTAssertEqual(ordinary.evidence.strategy, .fallback)
        XCTAssertEqual(ordinary.evidence.fallback?.code, "lr.previousForcedChoice")
    }

    func testUnknownTerminalPreflightDoesNotClaimCheckpointReuse() {
        let session = LRIncrementalRuntime()
        _ = session.parse(["a", "b"], table: alternativeSuffixTable)

        let rejected = session.parse(["a", "unknown"], table: alternativeSuffixTable)
        XCTAssertEqual(rejected.evidence.strategy, .fallback)
        XCTAssertEqual(rejected.evidence.fallback?.code, "lr.unknownTerminalPreflight")
        XCTAssertEqual(rejected.resumedAtToken, 0)
        XCTAssertEqual(rejected.reusedFrameCount, 0)
    }

    func testRuntimeTableArtifactIdentityIsStableAndContentSensitive() {
        XCTAssertEqual(
            alternativeSuffixTable.incrementalArtifactIdentity,
            alternativeSuffixTable.incrementalArtifactIdentity)
        let changed = LRRuntimeTable(
            terminals: alternativeSuffixTable.terminals + ["d"],
            productions: alternativeSuffixTable.productions,
            cells: alternativeSuffixTable.cells)
        XCTAssertNotEqual(
            alternativeSuffixTable.incrementalArtifactIdentity.fingerprint,
            changed.incrementalArtifactIdentity.fingerprint)
    }

    func testSharedDifferentialCampaignMatchesCleanLRExecution() throws {
        let table = alternativeSuffixTable
        let report = try DifferentialValidation.run(
            initialText: "a b",
            steps: [
                .init(
                    id: "change-suffix",
                    replacements: [.init(
                        range: .init(location: 2, length: 1), replacement: "c")]),
                .init(
                    id: "restore-suffix",
                    replacements: [.init(
                        range: .init(location: 2, length: 1), replacement: "b")]),
            ],
            makeParser: { LRIncrementalParser(whitespaceSeparated: table) },
            project: { $0.result })

        XCTAssertTrue(report.isEquivalent)
        XCTAssertEqual(report.observations.count, 3)

        var parser = LRIncrementalParser(whitespaceSeparated: alternativeSuffixTable)
        let initialSnapshot = SourceSnapshot(text: "a b")
        let initial = try parser.parse(initialSnapshot, previous: nil, change: nil)
        let change = try SourceEdit(
            baseRevision: initialSnapshot.revision,
            range: .init(location: 2, length: 1),
            replacement: "c").applying(to: initialSnapshot)
        let incremental = try parser.parse(
            change.after, previous: initial, change: change)
        XCTAssertEqual(incremental.evidence.strategy, .incremental)
    }

    func testWithholdingTransitionForcesCleanSharedContractExecution() throws {
        var parser = LRIncrementalParser(whitespaceSeparated: alternativeSuffixTable)
        let firstSnapshot = SourceSnapshot(text: "a b")
        let first = try parser.parse(firstSnapshot, previous: nil, change: nil)
        let replacement = SourceSnapshot(text: "a c", revision: .init(1))
        let reparsed = try parser.parse(replacement, previous: first, change: nil)

        XCTAssertEqual(reparsed.evidence.strategy, .full)
        XCTAssertEqual(reparsed.resumedAtToken, 0)
        XCTAssertEqual(reparsed.result.outcome, .accepted)
    }

    private var alternativeSuffixTable: LRRuntimeTable {
        LRRuntimeTable(
            terminals: ["a", "b", "c", "$"],
            productions: [
                .init(identity: "S-ab", lhs: "S", rhs: ["a", "b"]),
                .init(identity: "S-ac", lhs: "S", rhs: ["a", "c"]),
            ],
            cells: [
                .init(state: 0, symbol: "a", actions: [.shift(1)]),
                .init(state: 1, symbol: "b", actions: [.shift(2)]),
                .init(state: 1, symbol: "c", actions: [.shift(4)]),
                .init(state: 2, symbol: "$", actions: [.reduce("S-ab")]),
                .init(state: 4, symbol: "$", actions: [.reduce("S-ac")]),
                .init(state: 0, symbol: "S", actions: [.goTo(3)]),
                .init(state: 3, symbol: "$", actions: [.accept]),
            ])
    }
}
