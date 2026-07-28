import Grammar

/// The deterministic policy used to select an ACTION-table entry.
public enum LRActionResolution: String, Hashable, CustomStringConvertible {
    case soleAction
    case preferAccept
    case preferShift
    case generationOrder

    public var description: String {
        switch self {
        case .soleAction: "the cell contains one distinct action"
        case .preferAccept: "accept actions take precedence"
        case .preferShift: "shift actions take precedence"
        case .generationOrder: "the first deterministically ordered action is selected"
        }
    }
}

/// All inputs to, and the deterministic result of, selecting one ACTION cell.
public struct LRActionDecision: Hashable, CustomStringConvertible {
    public let identity: LRArtifactID
    public let state: Int
    public let lookahead: Terminal
    public let candidates: [LRActionCandidate]
    public let selectedAction: LRAction
    public let selectedCandidate: LRActionCandidate
    public let resolution: LRActionResolution

    public init(
        state: Int,
        lookahead: Terminal,
        candidates: [LRActionCandidate],
        selectedAction: LRAction,
        resolution: LRActionResolution,
        identity: LRArtifactID? = nil
    ) {
        precondition(!candidates.isEmpty, "An ACTION decision requires at least one candidate.")
        precondition(candidates.contains { $0.action == selectedAction }, "The selected action must originate in the candidate set.")
        self.state = state
        self.lookahead = lookahead
        self.candidates = candidates
        self.selectedAction = selectedAction
        self.selectedCandidate = candidates.first { $0.action == selectedAction }!
        self.resolution = resolution
        self.identity = identity ?? LRArtifactID(
            rawValue: "decision:\(lookahead.lrStableKey):\(candidates.map(\.identity.rawValue).sorted().joined(separator: "|")):\(selectedAction.lrStableKey):\(resolution.rawValue)"
        )
    }

    public var description: String { "\(selectedAction) because \(resolution)" }
}

public typealias LRActionDecisionTable = [Int: [Terminal: LRActionDecision]]
