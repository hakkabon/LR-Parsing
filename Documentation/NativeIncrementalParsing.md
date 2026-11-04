# Phase 10: Native LR adoption

Phase 10 makes deterministic LR checkpoint reuse a first-class implementation
of the shared incremental-parsing contracts. LR stack, symbol, and partial-tree
state remain private to LR-Parsing; the shared package receives only snapshots,
transitions, stable artifact identity, and parser-neutral operational evidence.

## Reuse boundary

`LRIncrementalRuntime` records a checkpoint immediately after every shifted
token. A checkpoint contains the consumed token index, execution step, complete
LR state and symbol stacks, partial syntax-node stack, and trace-frame boundary.
For a later token stream, the runtime resumes at the newest checkpoint at or
before the unchanged token prefix. Reductions at that cursor are replayed
because they depend on the new lookahead.

Checkpoint zero is deliberately treated as a full execution: it contains no
useful prior work. Reuse is also rejected when the table changes, the previous
execution rejected, recovered, conflicted, or looped, or either execution uses
a forced conflict decision. In each case the normal runtime starts at state zero
and reports a stable fallback reason.

With recovery disabled, unknown-terminal rejection occurs in the runtime's
global input preflight before any stack instruction executes. That path also
reports a fallback instead of claiming that a selected checkpoint was used.

## Shared evidence

Every result carries:

- an exact, deterministic, process-stable runtime-table identity;
- full, incremental, or fallback execution strategy;
- resident LR stack entries reused and rebuilt;
- trace frames reused and rebuilt;
- the engine-specific fallback reason when reuse was unsafe.

The runtime continues using its full structural table identity for the actual
reuse decision. The public fingerprint is evidence for clients and experiment
correlation, not a substitute for engine validation.

## Session adapter

`LRIncrementalParser` conforms to `IncrementalParsing.IncrementalParser` and
accepts a caller-owned tokenizer. This keeps language rules out of LR-Parsing.
The convenience whitespace tokenizer exists for table-level experiments only.
When a caller withholds either the previous result or the exact `SourceChange`,
the adapter resets and performs a full parse as required by the shared contract.

## Correctness gate

Differential campaigns construct a fresh LR parser at every source revision and
compare complete runtime results—tree, trace, outcome, diagnostics, and native
checkpoints—with the stateful execution. Targeted tests also cover artifact
replacement, invalid prior results, forced decisions, explicit full replacement,
and truthful operational evidence.
