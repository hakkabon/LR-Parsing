import Parser

/// LR specialization of the parser-independent deterministic result.
public typealias LRParseResult = DeterministicParseResult<LRParserTraceEvent>

/// Compatibility name retained for clients of the original LR API.
public typealias ParserOutcome = LRParseResult
public typealias ParserOutcomeStatus = ParseStatus
public typealias ParserDiagnostic = ParseDiagnostic

public enum RecoveryPolicy: Sendable {
    case none
    case panic
    case localRepair(maxEdits: Int)
}
