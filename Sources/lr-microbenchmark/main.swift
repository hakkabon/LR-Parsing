import Foundation
import LR_Parsing
import Parser

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard (1...2).contains(arguments.count), let name = arguments.first,
          let algorithm = LRParser.Algorithm(rawValue: name) else {
        throw NSError(
            domain: "lr-microbenchmark", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "usage: lr-microbenchmark lr0|slr|lalr|lr1 [output.json]"]
        )
    }
    #if DEBUG
    let configuration = ParserEngineMicrobenchmarkSuite.BuildConfiguration.debug
    #else
    let configuration = ParserEngineMicrobenchmarkSuite.BuildConfiguration.release
    #endif
    let report = try LRParserMicrobenchmarks.run(
        algorithm: algorithm, buildConfiguration: configuration
    )
    let data = try ParserEngineMicrobenchmarkCodec.encode(report)
    if arguments.count == 2 {
        try data.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("lr-microbenchmark: \(error)\n".utf8))
    exit(1)
}
