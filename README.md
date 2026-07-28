# LR-Parsing

A Swift package implementing a family of bottom-up **LR parsers** — LR(0), SLR(1), LALR(1), and canonical LR(1) — capable of parsing any context-free grammar (CFG) that belongs to the respective language class. Given a grammar and an input string the parser produces a typed, traversable **parse tree** that can be pretty-printed to the terminal, exported as a Graphviz DOT diagram, or transformed programmatically.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Grammar Formats](#grammar-formats)
- [Parsing Algorithms](#parsing-algorithms)
- [Parse Tree API](#parse-tree-api)
- [Command-Line Tool (lr-gtool)](#command-line-tool-lr-gtool)
- [Architecture](#architecture)
- [Improvements & Known Limitations](#improvements--known-limitations)
- [Installation](#installation)
- [License](#license)

---

## Overview

LR parsers are **shift-reduce** parsers that read input left-to-right and produce a **rightmost derivation** in reverse. This package implements all four major members of the LR family and lets you select the algorithm at runtime:

| Algorithm | Power       | Table Size | Notes                                      |  
|-----------|-------------|------------|--------------------------------------------|  
| LR(0)     | Weakest     | Smallest   | Reduces on every terminal; many conflicts  |  
| SLR(1)    | Moderate    | Small      | Uses FOLLOW sets to guide reductions       |  
| LALR(1)   | Strong      | Small      | Merges LR(1) states; used by Yacc/Bison    |  
| LR(1)     | Strongest   | Largest    | Full canonical LR; minimal conflicts       |  

---

## Features

- **Four parsing algorithms** selectable at runtime: `.lr0`, `.slr`, `.lr1`, `.lalr`
- **Multiple grammar input formats**: BNF, EBNF, WSN, and the package-native `.gen` format
- **Automatic table generation** — FIRST/FOLLOW sets, LR(0)/LR(1) item closure, GOTO construction, and LALR state merging are all computed from the grammar at init time
- **Typed parse trees** — `SyntaxTree<NonTerminal, Range<String.Index>>` with full generic map/filter/compress/explode traversal API
- **`TokenStream` integration** — drives from either GrammarTokenizer's hand-written tokenizer (`parse(_ string:)`, the default) or a DFA lexer bootstrapped from a `GrammarVocabulary` (`parse(stream:)`), interchangeably
- **Graphviz export** — render any parse tree as a PDF via `dot`
- **Colorized terminal output** via `TerminalColors`
- **Published generation artifacts** — states, items, transitions, ACTION/GOTO
  tables, conflicts, and shortest terminal witnesses are available through
  `LRParser.generate()`
- **Structured parser outcomes** — diagnostics and recovery edits distinguish
  clean acceptance, recovered acceptance, and rejection
- **Stable artifact identity** — productions, items, states, transitions, and
  conflicts carry deterministic semantic IDs; canonical generation ordering
  also keeps numeric state indices stable across repeated generation
- **Opt-in parser tracing** — structured start, lookahead inspection, shift,
  reduce, error, recovery, and accept events retain stable artifact references
- **Structured ACTION origins** — every pre-resolution ACTION candidate retains
  its originating LR item and whether it came from a terminal transition,
  LR(0) reduction, SLR FOLLOW set, LR(1)/LALR item lookahead, or augmented start
- **Recovery policies** — panic-mode synchronization and bounded single-token
  local repair are available through `parseOutcome`
- **`lr-gtool` CLI** — a standalone command-line executable for quick grammar experimentation

---

## Quick Start

### 1. Define a grammar in BNF

```swift
import Grammar
import LR_Parsing

// Classic arithmetic expression grammar
let bnf = """
<expr>   ::= <expr> "+" <term> | <term>
<term>   ::= <term> "*" <factor> | <factor>
<factor> ::= "(" <expr> ")" | "id"
"""

let grammar = try Grammar(bnf: bnf, start: "expr")
```

### 2. Create a parser and parse input

```swift
// Choose any algorithm: .lr0 | .slr | .lalr | .lr1
let parser = LRParser(grammar: grammar, algorithm: .lalr)

// Check membership
let valid = parser.recognizes("id + id * id")  // true

// Obtain a full parse tree
let tree = try parser.syntaxTree(for: "id + id * id")
print(tree)   // colorized tree printed to stdout
```

### 3. Map leaves back to source text

```swift
let source = "id + id * id"
let labeled = try parser.syntaxTree(for: source)
                        .mapLeafs { range in String(source[range]) }
print(labeled)
```

### Inspect generation and parse with recovery

```swift
let artifact = parser.generate()
print(artifact.states[0])
for conflict in artifact.conflicts {
    print(conflict, conflict.witness)
    print(conflict.decision as Any)
    let replay = artifact.replay(conflict)
    print(replay.reachedConflict, replay.steps)
}

let outcome = try parser.parseOutcome(
    "id + + id",
    recovery: .localRepair(maxEdits: 2)
)
print(outcome.status)
print(outcome.diagnostics)
print(outcome.recoveryEdits)
```

Enable structured runtime tracing when a replayable execution record is needed:

```swift
let traced = try parser.parseOutcome("id + id", tracing: true)
for event in traced.trace {
    print(event)
    print(event.state.identity)
    print(event.productionIdentity as Any)
}
```

Tracing is disabled by default. Artifact IDs are semantic strings and never use
Swift's process-randomized `Hasher`; they are suitable for cross-references,
snapshots, and future incremental-parser checkpoints. Identical duplicate
productions intentionally share one semantic production identity.

Generation never discards a conflicted automaton. The artifact retains all
conflicts for inspection; strict `syntaxTree(for:)` refuses to run a conflicted
table.

Every selected ACTION cell is backed by `LRAutomaton.actionCandidates`. A
conflict exposes the relevant subset directly through `LRConflict.candidates`,
so clients can explain competing actions without reconstructing their origins:

```swift
for candidate in conflict.candidates {
    print(candidate.action)
    print(candidate.reason)
    print(candidate.item)
    print(candidate.identity)
}
```

Candidates are retained before action deduplication. This means several LR items
may independently justify the same shift or reduction without being mislabeled
as a conflict.

`LRAutomaton.actionDecisions` records the deterministic choice for every ACTION
cell, including its candidates, selected action and resolution policy. The
current generator records sole-action, accept-preference, shift-preference and
deterministic generation-order decisions. A conflict also references its cell's
decision directly.

`LRAutomaton.replay(_:)` executes the conflict's shortest terminal witness using
those decisions and stops before the conflicted cell is applied. Its structured
result contains stack/state steps, the decision reached, and a failure reason if
the witness cannot reach the advertised state.

### 4. Parsing a `TokenStream` directly

`syntaxTree(for:)`/`parse(_ string:)` tokenize with GrammarTokenizer's `Tokenizer` by default. Any [Lexer](https://github.com/hakkabon/Lexer) `TokenStream` can be passed directly instead — including a DFA lexer bootstrapped from a `GrammarVocabulary`:

```swift
import Lexer

var builder = LexerBuilder()
builder.loadVocabulary(myGrammarVocabulary)
let lexer = try builder.build()

let stream = try LexerTokenStream(source: "id + id * id", lexer: lexer)
let tree = try parser.parse(stream: stream)
```

---

## Grammar Formats

The underlying `Grammar` dependency supports four textual notations:

### BNF (Backus-Naur Form)
```
<expr> ::= <expr> "+" <term> | <term>
<term> ::= <term> "*" <factor> | <factor>
<factor> ::= "(" <expr> ")" | "id"
```
```swift
let grammar = try Grammar(bnf: bnfString, start: "expr")
```

### EBNF (Extended BNF)
```swift
let grammar = try Grammar(ebnf: ebnfString, start: "start")
```

### WSN (Wirth Syntax Notation)
```swift
let grammar = try Grammar(wsn: wsnString, start: "start")
```

### `.gen` (Generic / Package-Native Format)
The start symbol is declared inside the file; no external `start` argument is needed.
```swift
let grammar = try Grammar(gen: genString)
```

---

## Parsing Algorithms

Select the algorithm when constructing `LRParser`:

```swift
LRParser(grammar: grammar, algorithm: .lr0)   // LR(0)
LRParser(grammar: grammar, algorithm: .slr)   // SLR(1)
LRParser(grammar: grammar, algorithm: .lalr)  // LALR(1)  ← recommended default
LRParser(grammar: grammar, algorithm: .lr1)   // Canonical LR(1)
```

**Choosing the right algorithm:**

- Start with **LALR(1)** — it handles almost all practical programming language grammars and produces the smallest tables.
- Upgrade to **LR(1)** only if LALR(1) reports reduce/reduce conflicts.
- Use **SLR(1)** for simple or pedagogical grammars.
- **LR(0)** is mainly useful for study purposes or trivially simple grammars.

---

## Parse Tree API

`ParseTree` is a type alias for `SyntaxTree<NonTerminal, Range<String.Index>>`.

### Tree Traversal

```swift
// Map inner nodes
let renamed = tree.mapNodes { nt in nt.name.uppercased() }

// Map leaves (e.g., resolve source ranges to strings)
let labeled = tree.mapLeafs { range in String(source[range]) }

// Filter subtrees
let filtered = tree.filter { nt in nt.name != "factor" }

// Find all nodes matching a predicate
let exprs = tree.allNodes { $0.name == "expr" }

// Compress single-child chains
let compact = tree.compressed()

// Explode (flatten) a node, passing its children to the parent
let flat = tree.explode { $0.name == "factor" }
```

### Graphviz Export

```swift
let dot = tree.mapLeafs { String(source[$0]) }.graphviz
// dot is a valid Graphviz digraph string; pipe it to `dot -Tpdf`
```

### Properties

```swift
tree.root      // NonTerminal? — the root non-terminal label
tree.leaf      // Leaf?        — the leaf value (if leaf node)
tree.children  // [ParseTree]? — direct children (if inner node)
tree.leafs     // [Leaf]       — all leaves in order
```

---

## Command-Line Tool (lr-gtool)

Build and run the included CLI:

```bash
swift build -c release
.build/release/lr-gtool --help
```

### Usage

```
lr-gtool parse <grammar-file> [options]

Arguments:
  <grammar-file>     Path to the grammar file (.bnf | .ebnf | .wsn | .gen)

Options:
  -s, --start        Start rule name (not needed for .gen files)
  -m, --method       Parsing algorithm: lr0 | slr | lalr | lr  [default: lr0]
  -i, --input        Input string or path to input file
  -a, --analysis     Output mode: tree | graph               [default: tree]
```

### Examples

```bash
# Parse an expression, display as ASCII tree
lr-gtool parse expr.bnf --start expr --method lalr --input "id + id * id" --analysis tree

# Parse from a file, open a PDF parse-tree diagram
lr-gtool parse expr.bnf --start expr --method lr1 --input ./sample.txt --analysis graph
```

---

## Architecture

```
LR-Parsing/
├── Sources/
│   ├── LR-Parsing/
│   │   ├── Parser.swift              # Parser protocol + ParseTree typealias
│   │   ├── ParserLogger.swift        # OSLog category
│   │   ├── LR-Parser/
│   │   │   ├── LRAction.swift        # shift / reduce / accept enum
│   │   │   ├── LRItem.swift          # LR(0)/LR(1) item with dot & lookahead
│   │   │   ├── LRTable.swift         # ACTION + GOTO table structures
│   │   │   ├── LRParser.swift        # Public parser: shift-reduce driver loop
│   │   │   └── TableGenerator.swift  # Closure, GOTO, state construction, LALR merge
│   │   └── Syntax-Tree/
│   │       ├── SyntaxTree.swift          # Generic recursive enum tree + operators
│   │       ├── SyntaxError.swift         # Structured error with line/column info
│   │       ├── SyntaxTreePrinter.swift   # Colorized ASCII tree renderer
│   │       └── SyntaxTreeGraphviz.swift  # DOT/Graphviz exporter
│   └── gtool/                     # lr-gtool executable target sources
│       ├── GrammarTool.swift         # CLI entry point (ArgumentParser)
│       ├── Parse.swift               # `parse` subcommand implementation
│       └── Definitions.swift         # CLI enums: Notation, Method, Analysis, Source
└── Tests/
    └── LR-ParsingTests/
        └── LR_ParsingTests.swift     # Test suite
```

**Key data-flow:**

```
Grammar (BNF/EBNF/WSN/gen)
    │
    ▼
LRTableGenerator
    ├── computeFirstSets / computeFollowSets
    ├── generateLR0States / generateLR1States
    ├── mergeToLALR  (LALR only)
    └── populate ACTION + GOTO tables
            │
            ▼
    LRParser.parse(source) / parse(stream:)
        ├── TokenizerStream or LexerTokenStream → StreamCursor
        ├── Shift-reduce loop (ACTION/GOTO lookup)
        └── SyntaxTree construction
                │
                ▼
        ParseTree  →  print / graphviz / transform
```

`parse(_ source:)` tokenizes with GrammarTokenizer's `Tokenizer` (via [Lexer](https://github.com/hakkabon/Lexer)'s `TokenizerStream`, configured with this parser's own `symbols` list) and hands the result to `parse<S: TokenStream>(stream: S)`, which runs the shift-reduce loop against any `TokenStream` — including a DFA lexer's `LexerTokenStream`. `StreamCursor` (in `LRParser.swift`) replaced direct `Tokenizer.next()` calls with an indexed pull over `TokenStream.terminal(at:)`; since LR parsing reads strictly left-to-right with one token of lookahead, this is a drop-in replacement, not an algorithmic change.

---

## Improvements & Known Limitations

See the detailed improvement notes in the repository's [IMPROVEMENTS.md](IMPROVEMENTS.md) for a full discussion. Key areas include:

- Table generation is re-run on every `parse()` call instead of being cached at `init` time
- LR(0) reduce-on-all-terminals strategy causes unnecessary conflicts for most grammars
- Conflict handling in `addShift` silently favors shift without propagating an error
- ~~The `extractTerminal` method is defined but never called in the parse loop~~ — resolved: both `extractTerminal` and the inline `getTerminal` closure it duplicated were removed when the parser adopted `TokenStream`; token-to-`Terminal` mapping now happens once, in `Lexer`'s `TokenizerStream`/`LexerTokenStream`, not in this package
- `SyntaxError` (with line/column information) is never thrown by `LRParser`; it throws `LRParseError` instead
- The LALR GOTO fixup comment notes a potential correctness issue when the merged state set doesn't exactly match generated goto sets
- `Unique.< ` comparator compares `id` to itself rather than `lhs.id` to `rhs.id`

---

## Installation

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/hakkabon/LR-Parsing.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "LR-Parsing", package: "LR-Parsing"),
        ]
    ),
]
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.  
