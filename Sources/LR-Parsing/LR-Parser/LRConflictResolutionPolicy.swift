import Grammar

/// Complete, immutable input supplied to a conflict-resolution policy.
public struct LRConflictResolutionContext {
    public let state: Int
    public let lookahead: Terminal
    public let candidates: [LRActionCandidate]
    public let actions: [LRAction]

    public init(state: Int, lookahead: Terminal, candidates: [LRActionCandidate], actions: [LRAction]) {
        self.state = state
        self.lookahead = lookahead
        self.candidates = candidates
        self.actions = actions
    }
}

/// A policy's deliberate resolution. `selectedAction == nil` installs an
/// error ACTION cell, which is useful for non-associative or forbidden forms.
public struct LRPolicyResolution: Hashable {
    public let selectedAction: LRAction?
    public let explanation: String

    public init(selectedAction: LRAction?, explanation: String) {
        self.selectedAction = selectedAction
        self.explanation = explanation
    }
}

/// Supplies application-specific decisions for conflicts not resolved by
/// declared precedence. Returning nil abstains and leaves fallback handling to
/// the generator. A selected action must occur in `context.actions`.
public protocol LRConflictResolutionPolicy {
    var name: String { get }
    func resolve(_ context: LRConflictResolutionContext) -> LRPolicyResolution?
}

/// Ready-made policies for interactive tools and simple deterministic parsers.
public enum LRStandardConflictPolicy: String, Hashable, CaseIterable, LRConflictResolutionPolicy {
    case preferShift
    case preferReduce
    case reject

    public var name: String { rawValue }

    public func resolve(_ context: LRConflictResolutionContext) -> LRPolicyResolution? {
        switch self {
        case .preferShift:
            guard let action = context.actions.first(where: { if case .shift = $0 { return true }; return false }) else { return nil }
            return LRPolicyResolution(selectedAction: action, explanation: "an explicit prefer-shift policy selected the shift candidate")
        case .preferReduce:
            guard let action = context.actions.first(where: { if case .reduce = $0 { return true }; return false }) else { return nil }
            return LRPolicyResolution(selectedAction: action, explanation: "an explicit prefer-reduce policy selected the first deterministic reduction candidate")
        case .reject:
            return LRPolicyResolution(selectedAction: nil, explanation: "an explicit reject policy installed an error ACTION cell")
        }
    }
}
