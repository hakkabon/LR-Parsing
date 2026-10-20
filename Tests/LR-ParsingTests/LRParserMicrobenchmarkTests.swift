import Parser
import Testing
@testable import LR_Parsing

@Test("Every LR algorithm owns a reproducible executable microbenchmark", arguments: LRParser.Algorithm.allCases)
func lrMicrobenchmark(algorithm: LRParser.Algorithm) throws {
    let report = try LRParserMicrobenchmarks.run(
        algorithm: algorithm,
        buildConfiguration: .release, warmupIterations: 0, measurementIterations: 3,
        environment: .init(
            operatingSystem: "test", architecture: "test",
            processorCount: 1, physicalMemoryBytes: 1
        )
    )
    #expect(report.suite.owner.repository == "LR-Parsing")
    #expect(report.suite.engineID == algorithm.rawValue)
    #expect(report.results.first?.counters["accepted"] == 1)
    #expect(report.results.first?.counters["leafCount"] == LRParserMicrobenchmarks.inputScale + 1)
}
