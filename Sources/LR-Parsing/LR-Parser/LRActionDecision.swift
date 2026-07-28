import Grammar

/// The deterministic policy used to select an ACTION-table entry.
public enum LRActionDecisionStatus: String, Hashable { case resolved, unresolved }

public enum LRActionResolution: Hashable, CustomStringConvertible {
    case soleAction
    case preferAcceptFallback
    case preferShiftFallback
    case generationOrderFallback
    case higherPrecedence(selected: Int, rejected: Int)
    case leftAssociative(level: Int)
    case rightAssociative(level: Int)
    case nonAssociative(level: Int)
    case policy(name: String, explanation: String)

    public var description: String {
        switch self {
        case .soleAction: "the cell contains one distinct action"
        case .preferAcceptFallback: "accept is selected by the unresolved fallback policy"
        case .preferShiftFallback: "shift is selected by the unresolved fallback policy"
        case .generationOrderFallback: "the first deterministically ordered action is selected by the unresolved fallback policy"
        case .higherPrecedence(let selected, let rejected): "precedence level \(selected) is higher than level \(rejected)"
        case .leftAssociative(let level): "precedence level \(level) is left associative, so reduce is selected"
        case .rightAssociative(let level): "precedence level \(level) is right associative, so shift is selected"
        case .nonAssociative(let level): "precedence level \(level) is non-associative, so the ACTION cell rejects input"
        case .policy(let name, let explanation): "policy \(name): \(explanation)"
        }
    }

    var stableKey: String {
        switch self {
        case .soleAction: "sole-action"
        case .preferAcceptFallback: "fallback-accept"
        case .preferShiftFallback: "fallback-shift"
        case .generationOrderFallback: "fallback-generation-order"
        case .higherPrecedence(let selected, let rejected): "precedence:\(selected)>\(rejected)"
        case .leftAssociative(let level): "left:\(level)"
        case .rightAssociative(let level): "right:\(level)"
        case .nonAssociative(let level): "nonassoc:\(level)"
        case .policy(let name, let explanation): "policy:\(name):\(explanation)"
        }
    }
}

/// All inputs to, and the deterministic result of, selecting one ACTION cell.
public struct LRActionDecision: Hashable, CustomStringConvertible {
    public let identity: LRArtifactID
    public let state: Int
    public let lookahead: Terminal
    public let candidates: [LRActionCandidate]
    public let selectedAction: LRAction?
    public let selectedCandidate: LRActionCandidate?
    public let resolution: LRActionResolution
    public let status: LRActionDecisionStatus

    public init(
        state: Int,
        lookahead: Terminal,
        candidates: [LRActionCandidate],
        selectedAction: LRAction?,
        resolution: LRActionResolution,
        status: LRActionDecisionStatus,
        identity: LRArtifactID? = nil
    ) {
        precondition(!candidates.isEmpty, "An ACTION decision requires at least one candidate.")
        precondition(selectedAction == nil || candidates.contains { $0.action == selectedAction }, "The selected action must originate in the candidate set.")
        self.state = state
        self.lookahead = lookahead
        self.candidates = candidates
        self.selectedAction = selectedAction
        self.selectedCandidate = selectedAction.flatMap { action in candidates.first { $0.action == action } }
        self.resolution = resolution
        self.status = status
        self.identity = identity ?? LRArtifactID(
            rawValue: "decision:\(lookahead.lrStableKey):\(candidates.map(\.identity.rawValue).sorted().joined(separator: "|")):\(selectedAction?.lrStableKey ?? "error"):\(resolution.stableKey):\(status.rawValue)"
        )
    }

    public var description: String {
        let selected = selectedAction.map { String(describing: $0) } ?? "error"
        return "\(selected) because \(resolution) [\(status.rawValue)]"
    }
}

public typealias LRActionDecisionTable = [Int: [Terminal: LRActionDecision]]
