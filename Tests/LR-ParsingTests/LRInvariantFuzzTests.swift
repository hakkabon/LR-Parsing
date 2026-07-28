import Testing
import Grammar
@testable import LR_Parsing

@Suite("LR generation invariants and grammar fuzzing")
struct LRInvariantFuzzTests {
    private func source(from terminals: [Terminal]) -> String {
        terminals.compactMap { terminal in
            if case .string(let value) = terminal { return value }
            if case .meta(.eof) = terminal { return nil }
            return terminal.description
        }.joined(separator: " ")
    }

    private func checkInvariants(_ artifact: LRAutomaton) {
        #expect(Set(artifact.conflicts.map(\.identity)).isDisjoint(with: Set(artifact.resolvedConflicts.map(\.identity))))
        #expect(artifact.allConflicts.count == artifact.conflicts.count + artifact.resolvedConflicts.count)
        #expect(artifact.conflicts.allSatisfy { !$0.isResolved })
        #expect(artifact.resolvedConflicts.allSatisfy { $0.isResolved })
        #expect(artifact.resolvedDecisions.count == artifact.resolvedConflicts.count)

        for (state, row) in artifact.actionCandidates {
            for (lookahead, candidates) in row {
                #expect(!candidates.isEmpty)
                #expect(Set(candidates.map(\.identity)).count == candidates.count)
                guard let decision = artifact.actionDecisions[state]?[lookahead] else {
                    Issue.record("Missing decision for state \(state) on \(lookahead)")
                    continue
                }
                #expect(decision.candidates == candidates)
                if let selected = decision.selectedAction {
                    #expect(candidates.contains { $0.action == selected })
                    #expect(artifact.actionTable[state]?[lookahead] == selected)
                } else {
                    #expect(artifact.actionTable[state]?[lookahead] == nil)
                }
            }
        }

        for conflict in artifact.allConflicts {
            #expect(Set(conflict.actions).count > 1)
            #expect(!conflict.candidates.isEmpty)
            #expect(conflict.decision != nil)
            let replay = artifact.replay(conflict)
            #expect(replay.reachedConflict)
            let branches = artifact.replayBranches(conflict)
            #expect(Set(branches.map(\.action)) == Set(conflict.actions))
        }
    }

    @Test("generation invariants hold across algorithms and resolution modes")
    func generationInvariants() throws {
        let simple = try Grammar(bnf: "<S> ::= \"a\" <S> | \"b\"", start: "S")
        let ambiguous = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let plus = Terminal(string: "+")
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .left, terminals: [plus])
        ])

        for algorithm in LRParser.Algorithm.allCases {
            checkInvariants(LRParser(grammar: simple, algorithm: algorithm).generate())
            checkInvariants(LRParser(grammar: ambiguous, algorithm: algorithm).generate())
            checkInvariants(LRParser(grammar: ambiguous, algorithm: algorithm, precedence: precedence).generate())
            checkInvariants(LRParser(grammar: ambiguous, algorithm: algorithm, resolutionPolicy: LRStandardConflictPolicy.preferReduce).generate())
        }
    }

    @Test("grammar fuzzer sentences remain accepted and artifact identities remain stable")
    func fuzzedSentences() throws {
        let grammar = try Grammar(bnf: """
            <E> ::= <E> "+" <T> | <T>
            <T> ::= <T> "*" <F> | <F>
            <F> ::= "(" <E> ")" | "id"
            """, start: "E")
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let fuzzer = GrammarFuzzer(grammar: grammar, options: .init(trace: false))
        let baseline = parser.generate()

        for _ in 0..<75 {
            let derivation = fuzzer.fuzz(start: grammar.start, conditions: .init(minNonTerminals: 1, maxNonTerminals: 8))
            let sentence = source(from: derivation.leafs)
            #expect(!sentence.isEmpty)
            #expect(parser.recognizes(sentence), "Fuzzer produced a rejected sentence: \(sentence)")
            let regenerated = parser.generate()
            #expect(regenerated.states.map(\.identity) == baseline.states.map(\.identity))
            #expect(regenerated.actionDecisions.values.flatMap(\.values).map(\.identity).sorted() == baseline.actionDecisions.values.flatMap(\.values).map(\.identity).sorted())
        }
    }
}
