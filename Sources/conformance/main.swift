import Foundation
import Grammar
import Lexer
import LR_Parsing
import Parser

private struct Corpus: Decodable {
    let schemaVersion: Int
    let grammars: [CorpusGrammar]
    let cases: [CorpusCase]
}

private struct CorpusGrammar: Decodable {
    let id: String
    let start: String
    let terminals: [String]
    let productions: [CorpusProduction]
    let precedence: [CorpusPrecedence]
}

private struct CorpusProduction: Decodable { let id: String; let lhs: String; let rhs: [String] }
private struct CorpusPrecedence: Decodable { let associativity: String; let terminals: [String] }
private struct CorpusCase: Decodable {
    let id: String
    let grammar: String
    let expectedTokenKinds: [String]
}

private struct Observation: Encodable {
    let id: String
    let status: String
    let root: String?
    let diagnostics: Int
    let recoveryEdits: Int
    let replay: ReplayObservation?
}

private struct ReplayObservation: Encodable {
    let terminal: String
    let events: [String]
    let productionIDs: [String]
}

private struct NormalizedTokenStream: TokenStream {
    let source: String
    let values: [(Terminal, Range<String.Index>)]
    var count: Int { values.count }

    init(kinds: [String]) {
        source = kinds.joined(separator: " ")
        var cursor = source.startIndex
        var result: [(Terminal, Range<String.Index>)] = []
        for kind in kinds {
            let end = source.index(cursor, offsetBy: kind.count)
            result.append((Terminal(string: kind), cursor..<end))
            cursor = end == source.endIndex ? end : source.index(after: end)
        }
        values = result
    }

    func terminal(at position: Int) throws -> (terminal: Terminal, range: Range<String.Index>) {
        values[position]
    }
}

private func makeGrammar(_ model: CorpusGrammar) -> (Grammar, LRPrecedenceSpecification?) {
    let terminalNames = Set(model.terminals)
    let productions = model.productions.map { production in
        Production(
            goal: NonTerminal(name: production.lhs),
            rule: production.rhs.map { symbol in
                terminalNames.contains(symbol)
                    ? .terminal(Terminal(string: symbol))
                    : .nonTerminal(NonTerminal(name: symbol))
            }
        )
    }
    let grammar = Grammar(
        productions: productions,
        start: NonTerminal(name: model.start),
        lexicalTokens: [:]
    )
    guard !model.precedence.isEmpty else { return (grammar, nil) }
    let levels = model.precedence.enumerated().map { index, level in
        LRPrecedenceLevel(
            index + 1,
            associativity: LRAssociativity(rawValue: level.associativity)!,
            terminals: Set(level.terminals.map { Terminal(string: $0) })
        )
    }
    return (grammar, LRPrecedenceSpecification(levels: levels))
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "lr-conformance", code: 2, userInfo: [NSLocalizedDescriptionKey: "usage: lr-conformance CORPUS OUTPUT"])
    }
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    guard (1...3).contains(corpus.schemaVersion) else { throw NSError(domain: "lr-conformance", code: 2) }
    let corpusGrammars = Dictionary(uniqueKeysWithValues: corpus.grammars.map { ($0.id, $0) })
    let grammars = Dictionary(uniqueKeysWithValues: corpus.grammars.map { ($0.id, makeGrammar($0)) })
    let observations = try corpus.cases.map { testCase -> Observation in
        guard let corpusGrammar = corpusGrammars[testCase.grammar],
              let (grammar, precedence) = grammars[testCase.grammar] else {
            throw NSError(domain: "lr-conformance", code: 2)
        }
        let parser = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence)
        let stream = NormalizedTokenStream(kinds: testCase.expectedTokenKinds)
        let result: LRParseResult
        do {
            result = try parser.parseOutcome(stream: stream, recovery: .localRepair(maxEdits: 8), tracing: true)
        } catch {
            result = .init(status: .rejected, tree: nil)
        }
        let status = switch result.status {
        case .accepted: "accepted"
        case .recovered: "acceptedWithRecovery"
        case .rejected: "rejected"
        }
        let identities = Dictionary(uniqueKeysWithValues: zip(grammar.productions, corpusGrammar.productions).map {
            ($0.0.lrArtifactID.rawValue, $0.1.id)
        })
        let replay = ReplayObservation(
            terminal: result.status == .rejected ? "reject" : "accept",
            events: result.trace.map { $0.parseContractEvent.kind.rawValue },
            productionIDs: result.trace.compactMap { event in
                event.productionIdentity.flatMap { identities[$0.rawValue] }
            }
        )
        return Observation(id: testCase.id, status: status, root: result.tree?.root?.name, diagnostics: result.diagnostics.count, recoveryEdits: result.recoveryEdits.count, replay: replay)
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(observations).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("lr-conformance: \(error)\n".utf8))
    exit(1)
}
