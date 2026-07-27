import Testing
import Grammar
@testable import LR_Parsing

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

    @Test("tracing is opt-in")
    func traceDisabledByDefault() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr).parseOutcome("a")
        #expect(outcome.trace.isEmpty)
    }
}
