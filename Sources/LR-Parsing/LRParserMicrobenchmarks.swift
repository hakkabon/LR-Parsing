import Foundation
import Grammar
import Parser

/// Engine-owned executable microbenchmarks for every supported LR construction/runtime.
public enum LRParserMicrobenchmarks {
    public static let ownerVersion = "0.2.5"
    public static let inputScale = 24

    private static let grammarSource = """
    <S> ::= 'id' <S> | 'end'
    """
    private static var input: String {
        (Array(repeating: "id", count: inputScale) + ["end"]).joined(separator: " ")
    }

    public static func suite(
        algorithm: LRParser.Algorithm,
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10
    ) -> ParserEngineMicrobenchmarkSuite {
        .init(
            owner: .init(repository: "LR-Parsing", version: ownerVersion),
            engineID: algorithm.rawValue,
            id: "lr-\(algorithm.rawValue)-core-v1",
            title: "\(algorithm.rawValue.uppercased()) runtime workloads",
            buildConfiguration: buildConfiguration,
            warmupIterations: warmupIterations,
            measurementIterations: measurementIterations,
            cases: [.init(
                id: "right-recursive-parse", title: "Parse a right-recursive token chain",
                operation: .parsing,
                boundary: "Tokenize and run the shift/reduce runtime with a pre-built \(algorithm.rawValue) table, producing one syntax tree.",
                workloadFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    grammarSource, input, "prebuilt-table", algorithm.rawValue, "syntax-tree"
                ]),
                scale: inputScale
            )]
        )
    }

    public static func run(
        algorithm: LRParser.Algorithm,
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10,
        environment: ParserEngineMicrobenchmarkEnvironment = .current
    ) throws -> ParserEngineMicrobenchmarkReport {
        let parser = LRParser(
            grammar: try Grammar(bnf: grammarSource, start: "S"), algorithm: algorithm
        )
        return try ParserEngineMicrobenchmarkRunner.run(
            suite(
                algorithm: algorithm, buildConfiguration: buildConfiguration,
                warmupIterations: warmupIterations,
                measurementIterations: measurementIterations
            ),
            environment: environment
        ) { _ in
            let tree = try parser.parse(input)
            let leaves = tree.leafs.count
            return .init(
                evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    "accepted", String(leaves), algorithm.rawValue
                ]),
                counters: ["accepted": 1, "leafCount": leaves, "tokenCount": inputScale + 1]
            )
        }
    }
}
