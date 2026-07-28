import Testing
import Grammar
@testable import LR_Parsing

@Suite("LR generation artifacts")
struct LRArtifactTests {
    @Test("artifact exposes states, transitions, ACTION, and GOTO")
    func exposesAutomaton() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()
        #expect(!artifact.states.isEmpty)
        #expect(!artifact.transitions.isEmpty)
        #expect(!artifact.actionTable.isEmpty)
        #expect(!artifact.gotoTable.isEmpty)
        #expect(artifact.conflicts.isEmpty)
    }

    @Test("ambiguous grammar reports conflict with witness")
    func conflictWitness() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()
        #expect(!artifact.conflicts.isEmpty)
        #expect(artifact.conflicts.allSatisfy { !$0.witness.isEmpty })
        #expect(artifact.conflicts.contains { $0.kind == .shiftReduce })
        let conflict = try #require(artifact.conflicts.first { $0.kind == .shiftReduce })
        #expect(conflict.candidates.count >= 2)
        #expect(conflict.candidates.contains { if case .terminalTransition = $0.reason { true } else { false } })
        #expect(conflict.candidates.contains { if case .itemLookahead = $0.reason { true } else { false } })
        #expect(conflict.candidates.allSatisfy { !$0.item.identity.rawValue.isEmpty })
    }

    @Test("every selected ACTION has one or more structured origins")
    func actionOriginsCoverTable() throws {
        let grammar = try makeArithmeticGrammar()
        let artifact = LRParser(grammar: grammar, algorithm: .slr).generate()
        for (state, entries) in artifact.actionTable {
            for terminal in entries.keys {
                let origins = artifact.actionCandidates[state]?[terminal] ?? []
                #expect(!origins.isEmpty)
                #expect(origins.allSatisfy { $0.state == state && $0.lookahead == terminal })
            }
        }
        #expect(artifact.actionCandidates.values.flatMap(\.values).flatMap { $0 }.contains {
            if case .slrFollow = $0.reason { true } else { false }
        })
    }
}

@Suite("Structured parser outcomes")
struct ParserOutcomeTests {
    @Test("clean parse returns accepted outcome")
    func accepted() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr).parseOutcome("a")
        #expect(outcome.status == .accepted)
        #expect(outcome.tree != nil)
        #expect(outcome.diagnostics.isEmpty)
    }

    @Test("bounded local repair deletes one unexpected token")
    func localRepair() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr)
            .parseOutcome("x a", recovery: .localRepair(maxEdits: 1))
        #expect(outcome.status == .recovered)
        #expect(outcome.recoveryEdits.count == 1)
        #expect(!outcome.diagnostics.isEmpty)
    }

    @Test("panic recovery skips to a viable token")
    func panic() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr)
            .parseOutcome("x y a", recovery: .panic)
        #expect(outcome.status == .recovered)
        #expect(outcome.recoveryEdits.count == 1)
    }

    @Test("bounded local repair inserts one missing token")
    func insertionRepair() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\" \"b\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr)
            .parseOutcome("b", recovery: .localRepair(maxEdits: 1))
        #expect(outcome.status == .recovered)
        #expect(outcome.recoveryEdits.count == 1)
        if case .insert = outcome.recoveryEdits[0] {} else { Issue.record("Expected insertion repair") }
    }
}
