import Testing
import Grammar
import Lexer
@testable import LR_Parsing

private struct IdentityTokenStream: TokenStream {
    let source: String
    let values: [(Terminal, Range<String.Index>)]
    var count: Int { values.count }

    init(_ kinds: [String]) {
        let text = kinds.joined(separator: " ")
        source = text
        var cursor = text.startIndex
        values = kinds.map { kind in
            let end = text.index(cursor, offsetBy: kind.count)
            defer { cursor = end == text.endIndex ? end : text.index(after: end) }
            return (Terminal(string: kind), cursor..<end)
        }
    }

    func terminal(at position: Int) throws -> (terminal: Terminal, range: Range<String.Index>) {
        values[position]
    }
}

@Suite("Stable LR artifact identity")
struct LRArtifactIdentityTests {
    @Test("repeated generation preserves semantic IDs and numeric state order")
    func repeatedGenerationIsDeterministic() throws {
        let grammar = try makeArithmeticGrammar()
        let first = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let second = LRParser(grammar: grammar, algorithm: .lalr).generate()

        #expect(first.states.map(\.identity) == second.states.map(\.identity))
        #expect(first.transitions.map(\.identity) == second.transitions.map(\.identity))
        #expect(first.conflicts.map(\.identity) == second.conflicts.map(\.identity))
        #expect(first.productions.map(\.identity) == second.productions.map(\.identity))
        #expect(Set(first.states.map(\.identity)).count == first.states.count)
    }

    @Test("semantic production ID does not use randomized hashes")
    func productionIdentityIsReadableAndStable() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let identity = try #require(grammar.productions.first).lrArtifactID
        #expect(identity.rawValue.hasPrefix("production:"))
        #expect(identity.rawValue.contains("1:S"))
        #expect(identity == grammar.productions[0].lrArtifactID)
    }

    @Test("equal declarations retain distinct occurrence identities")
    func duplicateProductionOccurrencesRemainDistinct() {
        let s = NonTerminal(name: "S")
        let production = Production(goal: s, rule: [.terminal(Terminal(string: "a"))])
        let grammar = Grammar(productions: [production, production], start: s, lexicalTokens: [:])
        let occurrences = LRParser(grammar: grammar, algorithm: .lalr).generate().productionOccurrences

        #expect(occurrences.count == 2)
        #expect(occurrences.map(\.ordinal) == [0, 1])
        #expect(occurrences.map(\.duplicateOrdinal) == [0, 1])
        #expect(Set(occurrences.map(\.identity)).count == 2)
    }
}

@Suite("LR parser tracing")
struct LRParserTracingTests {
    @Test("accepted parse records shifts, reductions, stable states, and acceptance")
    func acceptedTrace() throws {
        let grammar = try makeArithmeticGrammar()
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr).parseOutcome("id + id", tracing: true)
        #expect(outcome.status == .accepted)
        #expect(outcome.trace.first?.kind == .start)
        #expect(outcome.trace.contains { $0.kind == .shift })
        #expect(outcome.trace.contains { $0.kind == .reduce && $0.productionIdentity != nil })
        #expect(outcome.trace.last?.kind == .accept)
        #expect(outcome.trace.allSatisfy { !$0.state.identity.rawValue.isEmpty })
        #expect(outcome.trace.map(\.step) == Array(outcome.trace.indices))
    }

    @Test("rejection and repair are visible in trace")
    func recoveryTrace() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr)
            .parseOutcome("x a", recovery: .localRepair(maxEdits: 1), tracing: true)
        #expect(outcome.status == .recovered)
        #expect(outcome.trace.contains { $0.kind == .error })
        #expect(outcome.trace.contains { $0.kind == .recovery })
        #expect(outcome.trace.last?.kind == .accept)
    }

    @Test("token streams use the structured recovery contract")
    func tokenStreamRecovery() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr).parseOutcome(
            stream: IdentityTokenStream(["x", "a"]),
            recovery: .localRepair(maxEdits: 1),
            tracing: true
        )
        #expect(outcome.status == .recovered)
        #expect(outcome.recoveryEdits.count == 1)
        #expect(outcome.trace.last?.kind == .accept)
    }

    @Test("tracing is opt-in")
    func traceDisabledByDefault() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr).parseOutcome("a")
        #expect(outcome.trace.isEmpty)
    }
}
