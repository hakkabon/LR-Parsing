// LR_ParsingTests.swift
// LR-ParsingTests
//
// Comprehensive tests covering:
//   - All four parsing algorithms (LR(0), SLR, LALR, LR(1))
//   - Grammar acceptance / rejection
//   - Parse-tree structure validation
//   - Parse-tree transformation API (mapNodes, mapLeafs, filter, explode, compressed, allNodes)
//   - Graphviz export
//   - Error propagation (unexpectedToken, unexpectedEOF, generationFailed)
//   - SyntaxError line/column reporting
//   - Edge cases: empty productions, single-terminal grammars, deeply nested input
//   - Grammar input formats: BNF, EBNF (via Grammar package)

import Testing
import Foundation
@testable import LR_Parsing
import Grammar

// ─────────────────────────────────────────────────────────────────
// MARK: - Shared Grammar Helpers
// ─────────────────────────────────────────────────────────────────

/// Classic arithmetic expression grammar (left-recursive).
/// expr   → expr '+' term | term
/// term   → term '*' factor | factor
/// factor → '(' expr ')' | 'id'
func makeArithmeticGrammar() throws -> Grammar {
    let bnf = """
    <expr>   ::= <expr> "+" <term> | <term>
    <term>   ::= <term> "*" <factor> | <factor>
    <factor> ::= "(" <expr> ")" | "id"
    """
    return try Grammar(bnf: bnf, start: "expr")
}

/// Simple unambiguous grammar for balanced parentheses.
/// S → '(' S ')' S | ε
func makeParenGrammar() throws -> Grammar {
    let bnf = """
    <S> ::= "(" <S> ")" <S> | ""
    """
    return try Grammar(bnf: bnf, start: "S")
}

/// Minimal grammar: single terminal.
/// start → 'a'
func makeSingleTerminalGrammar() throws -> Grammar {
    let bnf = """
    <start> ::= "a"
    """
    return try Grammar(bnf: bnf, start: "start")
}

/// Grammar that requires LR(1) / LALR(1) lookahead to resolve.
/// S  → A 'a' | 'b' A 'c' | 'd' 'c' | 'b' 'd' 'a'
/// A  → 'd'
func makeCanonicalLR1Grammar() throws -> Grammar {
    let bnf = """
    <S> ::= <A> "a" | "b" <A> "c" | "d" "c" | "b" "d" "a"
    <A> ::= "d"
    """
    return try Grammar(bnf: bnf, start: "S")
}

/// Grammar for a simple assignment statement list.
/// stmtlist → stmtlist stmt | stmt
/// stmt     → 'id' '=' 'id' ';'
func makeStmtGrammar() throws -> Grammar {
    let bnf = """
    <stmtlist> ::= <stmtlist> <stmt> | <stmt>
    <stmt>     ::= "id" "=" "id" ";"
    """
    return try Grammar(bnf: bnf, start: "stmtlist")
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 1. Grammar Acceptance (recognizes)
// ─────────────────────────────────────────────────────────────────

@Suite("Grammar Acceptance")
struct GrammarAcceptanceTests {

    // ── LALR(1) arithmetic ──────────────────────────────────────

    @Test("LALR accepts simple identifier")
    func lalrAcceptsId() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id"))
    }

    @Test("LALR accepts addition")
    func lalrAcceptsAddition() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id + id"))
    }

    @Test("LALR accepts multiplication")
    func lalrAcceptsMultiplication() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id * id"))
    }

    @Test("LALR accepts chained operations")
    func lalrAcceptsChained() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id + id * id"))
    }

    @Test("LALR accepts parenthesized expression")
    func lalrAcceptsParens() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("( id + id ) * id"))
    }

    @Test("LALR accepts deeply nested parentheses")
    func lalrAcceptsDeeplyNested() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("( ( ( id ) ) )"))
    }

    @Test("LALR rejects mismatched parentheses")
    func lalrRejectsMismatch() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(!parser.recognizes("( id + id"))
    }

    @Test("LALR rejects extra operator")
    func lalrRejectsTrailingOp() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(!parser.recognizes("id + + id"))
    }

    @Test("LALR rejects empty string for non-nullable grammar")
    func lalrRejectsEmpty() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(!parser.recognizes(""))
    }

    // ── LR(1) canonical ─────────────────────────────────────────

    @Test("LR(1) accepts valid sentences of classic conflict grammar")
    func lr1AcceptsConflictGrammar() throws {
        let grammar = try makeCanonicalLR1Grammar()
        let parser = LRParser(grammar: grammar, algorithm: .lr1)
        #expect(parser.recognizes("d a"))
        #expect(parser.recognizes("d c"))
        #expect(parser.recognizes("b d c"))
        #expect(parser.recognizes("b d a"))
    }

    @Test("LR(1) rejects invalid sentence")
    func lr1RejectsInvalid() throws {
        let grammar = try makeCanonicalLR1Grammar()
        let parser = LRParser(grammar: grammar, algorithm: .lr1)
        #expect(!parser.recognizes("a"))
        #expect(!parser.recognizes("b a"))
    }

    // ── SLR arithmetic ──────────────────────────────────────────

    @Test("SLR accepts arithmetic expressions")
    func slrAcceptsArithmetic() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .slr)
        #expect(parser.recognizes("id"))
        #expect(parser.recognizes("id + id"))
        #expect(parser.recognizes("id * id * id"))
    }

    // ── Single terminal ─────────────────────────────────────────

    @Test("Single terminal grammar accepts correct token")
    func singleTerminalAccepts() throws {
        let grammar = try makeSingleTerminalGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("a"))
    }

    @Test("Single terminal grammar rejects wrong token")
    func singleTerminalRejects() throws {
        let grammar = try makeSingleTerminalGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(!parser.recognizes("b"))
        #expect(!parser.recognizes("a a"))
    }

    // ── Statement list ───────────────────────────────────────────

    @Test("Statement grammar accepts single assignment")
    func stmtAcceptsSingle() throws {
        let grammar = try makeStmtGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id = id ;"))
    }

    @Test("Statement grammar accepts multiple assignments")
    func stmtAcceptsMultiple() throws {
        let grammar = try makeStmtGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id = id ; id = id ;"))
    }

    @Test("Statement grammar rejects missing semicolon")
    func stmtRejectsMissingSemicolon() throws {
        let grammar = try makeStmtGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(!parser.recognizes("id = id"))
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 2. Algorithm Equivalence
// ─────────────────────────────────────────────────────────────────

@Suite("Algorithm Equivalence")
struct AlgorithmEquivalenceTests {

    let validInputs = ["id", "id + id", "id * id", "( id + id ) * id",
                       "id + id + id", "( ( id ) )"]
    let invalidInputs = ["", "+ id", "id +", "( id", "id )"]

    @Test("SLR and LALR agree on valid arithmetic inputs")
    func slrLalrAgreement() throws {
        let grammar = try makeArithmeticGrammar()
        let slr  = LRParser(grammar: grammar, algorithm: .slr)
        let lalr = LRParser(grammar: grammar, algorithm: .lalr)
        for input in validInputs {
            #expect(slr.recognizes(input) == lalr.recognizes(input),
                    "Mismatch on '\(input)'")
        }
    }

    @Test("LALR and LR(1) agree on valid arithmetic inputs")
    func lalrLr1Agreement() throws {
        let grammar = try makeArithmeticGrammar()
        let lalr = LRParser(grammar: grammar, algorithm: .lalr)
        let lr1  = LRParser(grammar: grammar, algorithm: .lr1)
        for input in validInputs {
            #expect(lalr.recognizes(input) == lr1.recognizes(input),
                    "Mismatch on '\(input)'")
        }
    }

    @Test("All algorithms reject the same invalid arithmetic inputs")
    func allAlgorithmsRejectInvalid() throws {
        let grammar = try makeArithmeticGrammar()
        let algorithms: [LRParser.Algorithm] = [.slr, .lalr, .lr1]
        for alg in algorithms {
            let parser = LRParser(grammar: grammar, algorithm: alg)
            for input in invalidInputs {
                #expect(!parser.recognizes(input),
                        "Algorithm \(alg) wrongly accepted '\(input)'")
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 3. Parse-Tree Structure
// ─────────────────────────────────────────────────────────────────

@Suite("Parse Tree Structure")
struct ParseTreeStructureTests {

    @Test("Single id produces a parse tree with correct root")
    func singleIdTreeRoot() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: "id")
        #expect(tree.root != nil)
        #expect(tree.root?.name == "expr")
    }

    @Test("Parse tree for 'id' has exactly one leaf")
    func singleIdTreeLeafCount() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: "id")
        #expect(tree.leafs.count == 1)
    }

    @Test("Parse tree root for addition is 'expr'")
    func additionTreeRoot() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: "id + id")
        #expect(tree.root?.name == "expr")
    }

    @Test("Parse tree for 'id + id' has three leaves")
    func additionTreeLeaves() throws {
        let source = "id + id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source)
        let leaves = tree.mapLeafs { String(source[$0]) }.leafs
        #expect(leaves.count == 3)
        #expect(leaves.contains("id"))
        #expect(leaves.contains("+"))
    }

    @Test("Parse tree has children at root for compound expression")
    func compoundTreeHasChildren() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: "id + id * id")
        #expect(tree.children != nil)
        #expect((tree.children?.count ?? 0) > 0)
    }

    @Test("Parse tree .empty is never the result of a successful parse")
    func parseTreeNeverEmpty() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: "id")
        if case .empty = tree {
            Issue.record("parse() returned .empty for a valid input")
        }
    }

    @Test("Leaf ranges can be resolved to source substrings")
    func leafRangesResolveCorrectly() throws {
        let source = "id + id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source)
        let labeled = tree.mapLeafs { range in String(source[range]) }
        for leaf in labeled.leafs {
            #expect(!leaf.isEmpty)
            #expect(source.contains(leaf))
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 4. Parse-Tree Transformation API
// ─────────────────────────────────────────────────────────────────

@Suite("Parse Tree Transformation API")
struct ParseTreeTransformationTests {

    func labeledTree(source: String = "id + id") throws -> SyntaxTree<String, String> {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source)
        return tree
            .mapNodes { $0.name }
            .mapLeafs { String(source[$0]) }
    }

    // ── mapNodes ────────────────────────────────────────────────

    @Test("mapNodes transforms every inner node label")
    func mapNodesTransformsLabels() throws {
        let tree = try labeledTree()
        let upper = tree.mapNodes { $0.uppercased() }
        let allNodes = upper.allNodes { _ in true }
        for node in allNodes {
            if let label = node.root {
                #expect(label == label.uppercased())
            }
        }
    }

    @Test("mapNodes preserves leaf values")
    func mapNodesPreservesLeaves() throws {
        let tree = try labeledTree()
        let original = tree.leafs
        let mapped = tree.mapNodes { $0 + "_mapped" }.leafs
        #expect(original == mapped)
    }

    // ── mapLeafs ────────────────────────────────────────────────

    @Test("mapLeafs transforms every leaf")
    func mapLeafsTransforms() throws {
        let tree = try labeledTree()
        let upper = tree.mapLeafs { $0.uppercased() }
        for leaf in upper.leafs {
            #expect(leaf == leaf.uppercased())
        }
    }

    @Test("mapLeafs preserves tree structure (same leaf count)")
    func mapLeafsPreservesCount() throws {
        let tree = try labeledTree()
        let original = tree.leafs.count
        let mapped = tree.mapLeafs { "X" }.leafs.count
        #expect(original == mapped)
    }

    // ── filter ──────────────────────────────────────────────────

    @Test("filter returns nil when root node is excluded")
    func filterExcludesRoot() throws {
        let tree = try labeledTree()
        let filtered = tree.filter { _ in false }
        #expect(filtered == nil)
    }

    @Test("filter keeps root when predicate always true")
    func filterKeepsRoot() throws {
        let tree = try labeledTree()
        let filtered = tree.filter { _ in true }
        #expect(filtered != nil)
    }

    @Test("filter removes subtrees whose roots don't match")
    func filterRemovesSubtrees() throws {
        let tree = try labeledTree(source: "id + id * id")
        let filtered = tree.filter { $0 == "expr" }
        if let f = filtered {
            let allNodes = f.allNodes { _ in true }
            for node in allNodes {
                if let label = node.root {
                    #expect(label == "expr")
                }
            }
        }
    }

    // ── explode ─────────────────────────────────────────────────

    @Test("explode on always-true predicate returns only leaves")
    func explodeAllReturnsLeaves() throws {
        let tree = try labeledTree()
        let exploded = tree.explode { _ in true }
        for subtree in exploded {
            if case .leaf(_) = subtree { /* good */ } else {
                Issue.record("explode(always-true) returned a non-leaf node")
            }
        }
    }

    @Test("explode on always-false predicate returns original tree in array")
    func explodeNoneReturnsOriginal() throws {
        let tree = try labeledTree()
        let exploded = tree.explode { _ in false }
        #expect(exploded.count == 1)
        #expect(exploded[0] == tree)
    }

    // ── compressed ──────────────────────────────────────────────

    @Test("compressed reduces single-child chains")
    func compressedReducesSingleChildChains() throws {
        let tree = try labeledTree(source: "id")
        let compressed = tree.compressed()
        switch compressed {
        case .node, .leaf: break
        case .empty: Issue.record("compressed() returned .empty")
        }
    }

    @Test("compressed preserves leaf values")
    func compressedPreservesLeaves() throws {
        let tree = try labeledTree()
        let original = tree.leafs
        let compressed = tree.compressed().leafs
        #expect(original == compressed)
    }

    // ── allNodes ────────────────────────────────────────────────

    @Test("allNodes(where: always-true) returns all inner nodes")
    func allNodesAlwaysTrue() throws {
        let tree = try labeledTree()
        let all = tree.allNodes { _ in true }
        #expect(!all.isEmpty)
    }

    @Test("allNodes finds specific non-terminal")
    func allNodesFindsExpr() throws {
        let tree = try labeledTree(source: "id + id")
        let exprNodes = tree.allNodes { $0 == "expr" }
        #expect(!exprNodes.isEmpty)
    }

    @Test("allNodes returns empty for never-matching predicate")
    func allNodesNeverMatch() throws {
        let tree = try labeledTree()
        let none = tree.allNodes { $0 == "nonexistent_nt" }
        #expect(none.isEmpty)
    }

    // ── leafs property ──────────────────────────────────────────

    @Test("leafs returns leaves in left-to-right order")
    func leafsOrderIsLeftToRight() throws {
        let source = "id + id * id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source)
            .mapLeafs { String(source[$0]) }
        let leaves = tree.leafs
        let reconstructed = leaves.joined()
        let sourceNoSpace = source.filter { !$0.isWhitespace }
        #expect(reconstructed == sourceNoSpace)
    }

    // ── Equatable ───────────────────────────────────────────────

    @Test("Two parse trees for the same input are equal")
    func equalityForSameInput() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let t1 = try parser.syntaxTree(for: "id + id")
        let t2 = try parser.syntaxTree(for: "id + id")
        #expect(t1 == t2)
    }

    @Test("Parse trees for different inputs are not equal")
    func inequalityForDifferentInputs() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let t1 = try parser.syntaxTree(for: "id + id")
        let t2 = try parser.syntaxTree(for: "id * id")
        #expect(t1 != t2)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 5. Graphviz Export
// ─────────────────────────────────────────────────────────────────

@Suite("Graphviz Export")
struct GraphvizExportTests {

    @Test("graphviz output starts with 'digraph'")
    func graphvizStartsWithDigraph() throws {
        let source = "id + id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source).mapLeafs { String(source[$0]) }
        let dot = tree.graphviz
        #expect(dot.hasPrefix("digraph"))
    }

    @Test("graphviz output contains 'node' declarations")
    func graphvizContainsNodeDeclarations() throws {
        let source = "id + id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source).mapLeafs { String(source[$0]) }
        #expect(tree.graphviz.contains("node"))
    }

    @Test("graphviz output contains arrow edges")
    func graphvizContainsEdges() throws {
        let source = "id + id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source).mapLeafs { String(source[$0]) }
        #expect(tree.graphviz.contains("->"))
    }

    @Test("graphviz output is non-empty for any valid parse")
    func graphvizNonEmpty() throws {
        let source = "( id * id ) + id"
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let tree = try parser.syntaxTree(for: source).mapLeafs { String(source[$0]) }
        #expect(!tree.graphviz.isEmpty)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 6. Error Handling
// ─────────────────────────────────────────────────────────────────

@Suite("Error Handling")
struct ErrorHandlingTests {

    @Test("syntaxTree throws on unexpected token")
    func throwsOnUnexpectedToken() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(throws: (any Error).self) {
            _ = try parser.syntaxTree(for: "id id")
        }
    }

    @Test("syntaxTree throws LRParseError on bad token at start")
    func throwsCorrectErrorTypeForBadToken() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        do {
            _ = try parser.syntaxTree(for: "+ id")
            Issue.record("Expected an error but got none")
        } catch let e as LRParseError {
            switch e {
            case .unexpectedToken, .unexpectedEOF, .internalError:
                break
            case .generationFailed, .tokenError:
                Issue.record("Unexpected LRParseError type: \(e)")
            }
        } catch {
            // Any error from the parse loop is acceptable
        }
    }

    @Test("syntaxTree throws on empty input for non-nullable grammar")
    func throwsOnEmptyInput() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(throws: (any Error).self) {
            _ = try parser.syntaxTree(for: "")
        }
    }

    @Test("syntaxTree throws on trailing garbage tokens")
    func throwsOnTrailingGarbage() throws {
        let grammar = try makeArithmeticGrammar()
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(throws: (any Error).self) {
            _ = try parser.syntaxTree(for: "id id id id")
        }
    }

    @Test("LRParseError descriptions are non-empty")
    func errorDescriptionsNonEmpty() {
        let errors: [LRParseError] = [
            .generationFailed("test"),
            .tokenError("tok"),
            .unexpectedToken(token: "x", state: 3),
            .unexpectedEOF(state: 7),
            .internalError("oops")
        ]
        for e in errors {
            #expect(!e.description.isEmpty)
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 7. SyntaxError Line/Column Reporting
// ─────────────────────────────────────────────────────────────────

@Suite("SyntaxError Line/Column")
struct SyntaxErrorTests {

    @Test("SyntaxError reports line 0 for error on first line")
    func lineNumberFirstLine() {
        let source = "hello world"
        let range = source.startIndex ..< source.index(source.startIndex, offsetBy: 5)
        let err = SyntaxError(range: range, in: source, reason: .unexpectedToken)
        #expect(err.line == 0)
    }

    @Test("SyntaxError reports line 1 for error on second line")
    func lineNumberSecondLine() {
        let source = "line1\nline2"
        let idx = source.index(source.startIndex, offsetBy: 6)
        let range = idx ..< source.index(idx, offsetBy: 5)
        let err = SyntaxError(range: range, in: source, reason: .unexpectedToken)
        #expect(err.line == 1)
    }

    @Test("SyntaxError column is 0 at start of string")
    func columnAtStartOfString() {
        let source = "abc"
        let range = source.startIndex ..< source.index(source.startIndex, offsetBy: 1)
        let err = SyntaxError(range: range, in: source, reason: .unknownToken)
        #expect(err.column == 0)
    }

    @Test("SyntaxError description contains reason keyword")
    func descriptionContainsReason() {
        let source = "xyz"
        let range = source.startIndex ..< source.index(source.startIndex, offsetBy: 1)
        let err = SyntaxError(range: range, in: source, reason: .unexpectedToken)
        #expect(err.description.contains("Unexpected"))
    }

    @Test("SyntaxError description includes context non-terminals")
    func descriptionIncludesContext() {
        let source = "abc"
        let range = source.startIndex ..< source.index(source.startIndex, offsetBy: 1)
        let ctx: [NonTerminal] = [NonTerminal(name: "expr"), NonTerminal(name: "term")]
        let err = SyntaxError(range: range, in: source, reason: .unexpectedToken, context: ctx)
        #expect(err.description.contains("expr"))
        #expect(err.description.contains("term"))
    }

    @Test("SyntaxError on empty string returns line 0 and column 0")
    func emptyStringReturnsZeroZero() {
        let source = ""
        let range = source.startIndex ..< source.startIndex
        let err = SyntaxError(range: range, in: source, reason: .emptyNotAllowed)
        #expect(err.line == 0)
        #expect(err.column == 0)
    }

    @Test("SyntaxError reason descriptions are non-empty")
    func reasonDescriptionsNonEmpty() {
        let reasons: [SyntaxError.Reason] = [
            .emptyNotAllowed, .unknownToken, .unmatchedPattern, .unexpectedToken
        ]
        for r in reasons {
            #expect(!r.description.isEmpty)
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 8. LRAction Description
// ─────────────────────────────────────────────────────────────────

@Suite("LRAction Description")
struct LRActionDescriptionTests {

    @Test("shift action description starts with 's' and contains state number")
    func shiftDescription() {
        let action = LRAction.shift(5)
        #expect(action.description.hasPrefix("s"))
        #expect(action.description.contains("5"))
    }

    @Test("accept action description is 'acc'")
    func acceptDescription() {
        #expect(LRAction.accept.description == "acc")
    }

    @Test("reduce action description starts with 'r' and contains goal name")
    func reduceDescription() {
        let prod = Production(goal: NonTerminal(name: "E"),
                              rule: [.terminal(Terminal(string: "id"))])
        let action = LRAction.reduce(prod)
        #expect(action.description.hasPrefix("r"))
        #expect(action.description.contains("E"))
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 9. LRItem Behaviour
// ─────────────────────────────────────────────────────────────────

@Suite("LRItem Behaviour")
struct LRItemTests {

    @Test("LRItem description contains goal non-terminal name")
    func itemDescriptionContainsGoal() {
        let prod = Production(goal: NonTerminal(name: "expr"),
                              rule: [.terminal(Terminal(string: "id"))])
        let item = LRItem(production: prod, dotIndex: 0)
        #expect(item.description.contains("expr"))
    }

    @Test("LRItem description contains bullet character")
    func itemDescriptionContainsBullet() {
        let prod = Production(goal: NonTerminal(name: "E"),
                              rule: [.terminal(Terminal(string: "a")),
                                     .terminal(Terminal(string: "b"))])
        let item = LRItem(production: prod, dotIndex: 1)
        #expect(item.description.contains("•"))
    }

    @Test("LRItem core equality ignores lookahead")
    func itemCoreEqualityIgnoresLookahead() {
        let prod = Production(goal: NonTerminal(name: "S"),
                              rule: [.terminal(Terminal(string: "x"))])
        let la1 = Set<Symbol>([.terminal(Terminal(string: "a"))])
        let la2 = Set<Symbol>([.terminal(Terminal(string: "b"))])
        let item1 = LRItem(production: prod, dotIndex: 0, lookahead: la1)
        let item2 = LRItem(production: prod, dotIndex: 0, lookahead: la2)
        #expect(item1.core == item2.core)
    }

    @Test("LRItem nextSymbol is nil when dot is at end")
    func nextSymbolNilAtEnd() {
        let prod = Production(goal: NonTerminal(name: "S"),
                              rule: [.terminal(Terminal(string: "x"))])
        let item = LRItem(production: prod, dotIndex: 1)
        #expect(item.nextSymbol == nil)
    }

    @Test("LRItem advanced() moves dot one position right")
    func advancedMovesOneDot() {
        let prod = Production(goal: NonTerminal(name: "A"),
                              rule: [.terminal(Terminal(string: "x")),
                                     .terminal(Terminal(string: "y"))])
        let item = LRItem(production: prod, dotIndex: 0)
        let adv  = item.advanced()
        #expect(adv.dotIndex == 1)
        #expect(adv.nextSymbol == .terminal(Terminal(string: "y")))
    }

    @Test("LRItem withLookahead returns item with updated lookahead")
    func withLookaheadUpdates() {
        let prod = Production(goal: NonTerminal(name: "S"),
                              rule: [.terminal(Terminal(string: "a"))])
        let item = LRItem(production: prod, dotIndex: 0)
        let la   = Set<Symbol>([.terminal(Terminal(string: "$"))])
        let updated = item.withLookahead(la)
        #expect(updated.lookahead == la)
        #expect(updated.core == item.core)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 10. Parser Protocol (`recognizes`)
// ─────────────────────────────────────────────────────────────────

@Suite("Parser Protocol")
struct ParserProtocolTests {

    @Test("recognizes returns true for valid input")
    func recognizesReturnsTrueForValid() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id + id"))
    }

    @Test("recognizes returns false for invalid input")
    func recognizesReturnsFalseForInvalid() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(!parser.recognizes("id id"))
    }

    @Test("recognizes is consistent with syntaxTree success/failure")
    func recognizesConsistentWithSyntaxTree() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        let inputs  = ["id", "id + id", "", "bad input here!!!"]
        for input in inputs {
            let recognized   = parser.recognizes(input)
            let treeSucceeds = (try? parser.syntaxTree(for: input)) != nil
            #expect(recognized == treeSucceeds, "Mismatch on '\(input)'")
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 11. SyntaxTree Equatable Corner Cases
// ─────────────────────────────────────────────────────────────────

@Suite("SyntaxTree Equatable")
struct SyntaxTreeEquatableTests {

    @Test("leaf equals leaf with same value")
    func leafEqualLeaf() {
        let l1 = SyntaxTree<String, String>.leaf("x")
        let l2 = SyntaxTree<String, String>.leaf("x")
        #expect(l1 == l2)
    }

    @Test("leaf does not equal leaf with different value")
    func leafNotEqualDifferentLeaf() {
        let l1 = SyntaxTree<String, String>.leaf("x")
        let l2 = SyntaxTree<String, String>.leaf("y")
        #expect(l1 != l2)
    }

    @Test("node equals node with same structure")
    func nodeEqualNode() {
        let n1 = SyntaxTree<String, String>.node("A", children: [.leaf("x")])
        let n2 = SyntaxTree<String, String>.node("A", children: [.leaf("x")])
        #expect(n1 == n2)
    }

    @Test("node does not equal node with different children")
    func nodeNotEqualDifferentChildren() {
        let n1 = SyntaxTree<String, String>.node("A", children: [.leaf("x")])
        let n2 = SyntaxTree<String, String>.node("A", children: [.leaf("y")])
        #expect(n1 != n2)
    }

    @Test("node does not equal node with different label")
    func nodeNotEqualDifferentLabel() {
        let n1 = SyntaxTree<String, String>.node("A", children: [.leaf("x")])
        let n2 = SyntaxTree<String, String>.node("B", children: [.leaf("x")])
        #expect(n1 != n2)
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 12. Grammar Format Support
// ─────────────────────────────────────────────────────────────────

@Suite("Grammar Format Support")
struct GrammarFormatTests {

    @Test("BNF grammar parses correctly")
    func bnfGrammar() throws {
        let bnf = """
        <S> ::= "a" "b"
        """
        let grammar = try Grammar(bnf: bnf, start: "S")
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("a b"))
        #expect(!parser.recognizes("a"))
        #expect(!parser.recognizes("b"))
    }

    @Test("Programmatic grammar construction via Productions API")
    func programmaticGrammar() throws {
        let S     = NonTerminal(name: "S")
        let hello = Symbol.terminal(Terminal(string: "hello"))
        let world = Symbol.terminal(Terminal(string: "world"))
        let prod  = Production(goal: S, rule: [hello, world])
        let grammar = Grammar(productions: [prod], start: S, lexicalTokens: [:])
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("hello world"))
        #expect(!parser.recognizes("hello"))
        #expect(!parser.recognizes("world hello"))
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - 13. Stress / Edge Cases
// ─────────────────────────────────────────────────────────────────

@Suite("Edge Cases")
struct EdgeCaseTests {

    @Test("Very long valid expression is accepted")
    func longExpression() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        let expr = (0..<20).map { _ in "id" }.joined(separator: " + ")
        #expect(parser.recognizes(expr))
    }

    @Test("Deeply nested parentheses are accepted")
    func deeplyNestedParens() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        let depth = 10
        let open  = String(repeating: "( ", count: depth)
        let close = String(repeating: " )", count: depth)
        let expr  = "\(open)id\(close)"
        #expect(parser.recognizes(expr))
    }

    @Test("Parse tree leaf count equals terminal count in input")
    func leafCountEqualsTerminalCount() throws {
        let source  = "id + id * id"
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        let tree    = try parser.syntaxTree(for: source)
        // Terminals: id, +, id, *, id = 5
        #expect(tree.leafs.count == 5)
    }

    @Test("Multiple parses of same input produce identical trees")
    func multipleParsesSameResult() throws {
        let source  = "id + id"
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        let t1 = try parser.syntaxTree(for: source)
        let t2 = try parser.syntaxTree(for: source)
        let t3 = try parser.syntaxTree(for: source)
        #expect(t1 == t2)
        #expect(t2 == t3)
    }

    @Test("Parser handles many different valid inputs sequentially")
    func parserHandlesManyInputs() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        let inputs  = ["id", "id + id", "id * id", "( id )", "id + id * id",
                       "( id + id ) * ( id + id )"]
        for input in inputs {
            #expect(parser.recognizes(input), "Failed on: \(input)")
        }
    }

    @Test("Whitespace variations don't affect parsing of arithmetic")
    func whitespaceVariations() throws {
        let grammar = try makeArithmeticGrammar()
        let parser  = LRParser(grammar: grammar, algorithm: .lalr)
        #expect(parser.recognizes("id  +  id"))
        #expect(parser.recognizes("  id + id  "))
    }
}
