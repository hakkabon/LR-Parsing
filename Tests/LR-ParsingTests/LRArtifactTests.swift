import Testing
import Grammar
import Parser
@testable import LR_Parsing

private struct TestConflictPolicy: LRConflictResolutionPolicy {
    let name = "test-last-action"
    func resolve(_ context: LRConflictResolutionContext) -> LRPolicyResolution? {
        context.actions.last.map { LRPolicyResolution(selectedAction: $0, explanation: "selected the last deterministic action") }
    }
}

@Suite("LR generation artifacts")
struct LRArtifactTests {
    @Test("cached artifacts satisfy state, transition, GOTO, and ACTION invariants")
    func artifactInvariants() throws {
        let grammars = [
            try Grammar(bnf: "<S> ::= \"a\" <S> | \"b\"", start: "S"),
            try Grammar(
                bnf: """
                <S> ::= <L> \"=\" <R> | <R>
                <L> ::= \"*\" <R> | \"id\"
                <R> ::= <L>
                """,
                start: "S"
            ),
        ]

        for grammar in grammars {
            for algorithm in LRParser.Algorithm.allCases {
                let parser = LRParser(grammar: grammar, algorithm: algorithm)
                let first = parser.generate()
                let second = parser.generate()

                #expect(first.states.map(\.identity) == second.states.map(\.identity))
                #expect(first.transitions.map(\.identity) == second.transitions.map(\.identity))
                #expect(first.states.map(\.id) == Array(first.states.indices))
                #expect(Set(first.states.map(\.identity)).count == first.states.count)

                let stateIDs = Set(first.states.map(\.id))
                for transition in first.transitions {
                    #expect(stateIDs.contains(transition.source))
                    #expect(stateIDs.contains(transition.target))
                    switch transition.symbol {
                    case .terminal(let terminal):
                        let candidates = first.actionCandidates[transition.source]?[terminal] ?? []
                        #expect(candidates.contains { $0.action == .shift(transition.target) })
                    case .nonTerminal(let nonterminal):
                        #expect(first.gotoTable[transition.source]?[nonterminal] == transition.target)
                    case .metaSymbol:
                        Issue.record("LR automata must not contain meta-symbol transitions")
                    }
                }

                for (state, row) in first.actionTable {
                    #expect(stateIDs.contains(state))
                    for (lookahead, action) in row {
                        let decision = try #require(first.actionDecisions[state]?[lookahead])
                        #expect(decision.selectedAction == action)
                        #expect(decision.candidates.contains { $0.action == action })
                    }
                }
            }
        }
    }

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

    @Test("every ACTION has an explicit deterministic decision")
    func actionDecisions() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()

        for (state, row) in artifact.actionTable {
            for (lookahead, action) in row {
                let decision = try #require(artifact.actionDecisions[state]?[lookahead])
                #expect(decision.selectedAction == action)
                #expect(decision.candidates.contains { $0.action == action })
            }
        }
        let conflict = try #require(artifact.conflicts.first { $0.kind == .shiftReduce })
        #expect(conflict.decision?.resolution == .preferShiftFallback)
        #expect(conflict.status == .unresolved)
    }

    @Test("left associativity resolves a shift-reduce conflict")
    func leftAssociativity() throws {
        let minus = Terminal(string: "-")
        let grammar = try Grammar(bnf: "<E> ::= <E> \"-\" <E> | \"id\"", start: "E")
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .left, terminals: [minus])
        ])
        let parser = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence)
        let artifact = parser.generate()

        #expect(artifact.unresolvedConflicts.isEmpty)
        #expect(artifact.resolvedConflicts.count == 1)
        #expect(artifact.resolvedConflicts[0].decision?.resolution == .leftAssociative(level: 1))
        if case .reduce = artifact.resolvedConflicts[0].decision?.selectedAction {} else { Issue.record("Expected left associativity to reduce") }
        #expect(parser.recognizes("id - id - id"))
    }

    @Test("right associativity resolves a shift-reduce conflict")
    func rightAssociativity() throws {
        let power = Terminal(string: "^")
        let grammar = try Grammar(bnf: "<E> ::= <E> \"^\" <E> | \"id\"", start: "E")
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .right, terminals: [power])
        ])
        let artifact = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence).generate()

        #expect(artifact.unresolvedConflicts.isEmpty)
        #expect(artifact.resolvedConflicts[0].decision?.resolution == .rightAssociative(level: 1))
        if case .shift = artifact.resolvedConflicts[0].decision?.selectedAction {} else { Issue.record("Expected right associativity to shift") }
    }

    @Test("non-associativity resolves to an error ACTION cell")
    func nonAssociativity() throws {
        let less = Terminal(string: "<")
        let grammar = try Grammar(bnf: "<E> ::= <E> \"<\" <E> | \"id\"", start: "E")
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .nonAssociative, terminals: [less])
        ])
        let parser = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence)
        let artifact = parser.generate()
        let conflict = try #require(artifact.resolvedConflicts.first)

        #expect(conflict.decision?.resolution == .nonAssociative(level: 1))
        #expect(conflict.decision?.selectedAction == nil)
        #expect(artifact.actionTable[conflict.state]?[conflict.lookahead] == nil)
        #expect(!parser.recognizes("id < id < id"))
    }

    @Test("higher terminal precedence resolves expression conflicts")
    func precedenceLevels() throws {
        let plus = Terminal(string: "+")
        let star = Terminal(string: "*")
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | <E> \"*\" <E> | \"id\"", start: "E")
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .left, terminals: [plus]),
            LRPrecedenceLevel(2, associativity: .left, terminals: [star])
        ])
        let parser = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence)
        let artifact = parser.generate()

        #expect(artifact.conflicts.isEmpty)
        #expect(artifact.allConflicts.count == 4)
        #expect(artifact.resolvedDecisions.count == 4)
        #expect(artifact.unresolvedConflicts.isEmpty)
        #expect(artifact.resolvedConflicts.allSatisfy { $0.status == .resolved })
        #expect(parser.recognizes("id + id * id"))
    }

    @Test("explicit reduce policy resolves an otherwise unresolved conflict")
    func explicitReducePolicy() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let parser = LRParser(grammar: grammar, algorithm: .lalr, resolutionPolicy: LRStandardConflictPolicy.preferReduce)
        let artifact = parser.generate()
        let conflict = try #require(artifact.resolvedConflicts.first)

        #expect(artifact.unresolvedConflicts.isEmpty)
        #expect(conflict.decision?.status == .resolved)
        if case .policy(let name, _) = conflict.decision?.resolution { #expect(name == "preferReduce") }
        else { Issue.record("Expected policy resolution provenance") }
        if case .reduce = conflict.decision?.selectedAction {} else { Issue.record("Expected policy to select reduce") }
        #expect(parser.recognizes("id + id + id"))
    }

    @Test("explicit reject policy installs an error cell")
    func explicitRejectPolicy() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let parser = LRParser(grammar: grammar, algorithm: .lalr, resolutionPolicy: LRStandardConflictPolicy.reject)
        let artifact = parser.generate()
        let conflict = try #require(artifact.resolvedConflicts.first)

        #expect(conflict.decision?.selectedAction == nil)
        #expect(artifact.actionTable[conflict.state]?[conflict.lookahead] == nil)
        #expect(!parser.recognizes("id + id + id"))
    }

    @Test("declared precedence is authoritative before a general policy")
    func precedenceBeforePolicy() throws {
        let plus = Terminal(string: "+")
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .left, terminals: [plus])
        ])
        let artifact = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence, resolutionPolicy: LRStandardConflictPolicy.preferShift).generate()
        let conflict = try #require(artifact.resolvedConflicts.first)

        #expect(conflict.decision?.resolution == .leftAssociative(level: 1))
        if case .reduce = conflict.decision?.selectedAction {} else { Issue.record("Expected precedence to select reduce") }
    }

    @Test("client-defined policy receives structured conflict context")
    func customPolicy() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr, resolutionPolicy: TestConflictPolicy()).generate()
        let conflict = try #require(artifact.resolvedConflicts.first)

        #expect(conflict.decision?.selectedAction == conflict.actions.last)
        if case .policy(let name, let explanation) = conflict.decision?.resolution {
            #expect(name == "test-last-action")
            #expect(explanation.contains("last deterministic action"))
        } else { Issue.record("Expected custom policy provenance") }
    }

    @Test("shortest conflict witness replays to its decision point")
    func conflictReplay() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let conflict = try #require(artifact.conflicts.first { $0.kind == .shiftReduce })
        let replay = artifact.replay(conflict)

        #expect(replay.reachedConflict)
        #expect(replay.failure == nil)
        #expect(replay.decision?.selectedAction == conflict.decision?.selectedAction)
        #expect(replay.steps.last?.kind == .conflict)
        #expect(replay.steps.last?.state.index == conflict.state)
        #expect(replay.steps.last?.lookahead == conflict.lookahead)
    }

    @Test("replay forces every competing branch from the same conflict point")
    func conflictBranchReplay() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let conflict = try #require(artifact.conflicts.first)
        let branches = artifact.replayBranches(conflict)

        #expect(branches.count == conflict.actions.count)
        #expect(Set(branches.map(\.action)) == Set(conflict.actions))
        #expect(branches.filter(\.wasSelected).count == 1)
        #expect(branches.allSatisfy { $0.steps.last?.kind != .conflict })
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
        let diagnostic = try #require(outcome.diagnostics.first)
        #expect(diagnostic.reason == .unexpectedToken)
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 1)
        #expect(diagnostic.parserState != nil)
        #expect(diagnostic.found?.description == "\"x\"")
        #expect(!DiagnosticReporter().string(for: outcome.diagnostics).isEmpty)
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

    @Test("local insertion repair chooses a stable terminal")
    func deterministicInsertionRepair() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"b\" \"z\" | \"a\" \"z\"", start: "S")
        let outcome = try LRParser(grammar: grammar, algorithm: .lalr)
            .parseOutcome("z", recovery: .localRepair(maxEdits: 1))
        #expect(outcome.status == .recovered)
        #expect(outcome.recoveryEdits.count == 1)
        if case .insert(let terminal, _) = outcome.recoveryEdits[0] {
            #expect(terminal == Terminal(string: "a"))
        } else {
            Issue.record("Expected insertion repair")
        }
    }
}
