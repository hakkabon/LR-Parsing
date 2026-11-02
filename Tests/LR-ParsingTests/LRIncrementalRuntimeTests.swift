import XCTest
@testable import LR_Parsing

final class LRIncrementalRuntimeTests: XCTestCase {
    func testResumesFromLastUnchangedPrefixCheckpoint() {
        let table = LRRuntimeTable(
            terminals: ["a", "b", "c", "$"],
            productions: [.init(identity: "S-ab", lhs: "S", rhs: ["a", "b"])],
            cells: [
                .init(state: 0, symbol: "a", actions: [.shift(1)]),
                .init(state: 1, symbol: "b", actions: [.shift(2)]),
                .init(state: 2, symbol: "$", actions: [.reduce("S-ab")]),
                .init(state: 0, symbol: "S", actions: [.goTo(3)]),
                .init(state: 3, symbol: "$", actions: [.accept]),
            ]
        )
        let session = LRIncrementalRuntime()
        XCTAssertEqual(session.parse(["a", "b"], table: table).result.outcome, .accepted)
        let edited = session.parse(["a", "c"], table: table)
        XCTAssertEqual(edited.resumedAtToken, 1)
        XCTAssertGreaterThan(edited.reusedFrameCount, 0)
        if case .rejected = edited.result.outcome {} else { XCTFail("Expected rejection") }
    }
}
