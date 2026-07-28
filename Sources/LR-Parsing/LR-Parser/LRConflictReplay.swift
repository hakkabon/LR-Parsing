import Grammar

public struct LRConflictReplayStep: Hashable, CustomStringConvertible {
    public enum Kind: String, Hashable { case shift, reduce, accept, conflict }

    public let index: Int
    public let kind: Kind
    public let tokenIndex: Int
    public let lookahead: Terminal
    public let state: LRTraceState
    public let stack: [LRTraceState]
    public let action: LRAction?

    public init(index: Int, kind: Kind, tokenIndex: Int, lookahead: Terminal, state: LRTraceState, stack: [LRTraceState], action: LRAction?) {
        self.index = index
        self.kind = kind
        self.tokenIndex = tokenIndex
        self.lookahead = lookahead
        self.state = state
        self.stack = stack
        self.action = action
    }

    public var description: String {
        let states = stack.map { String($0.index) }.joined(separator: " ")
        let suffix = action.map { ", action \($0)" } ?? ""
        return "[\(index)] \(kind.rawValue) @ token \(tokenIndex), state \(state.index), lookahead \(lookahead), stack [\(states)]\(suffix)"
    }
}

/// A deterministic replay of a conflict's shortest witness.
public struct LRConflictReplay {
    public let conflict: LRConflict
    public let decision: LRActionDecision?
    public let steps: [LRConflictReplayStep]
    public let reachedConflict: Bool
    public let failure: String?

    public init(conflict: LRConflict, decision: LRActionDecision?, steps: [LRConflictReplayStep], reachedConflict: Bool, failure: String? = nil) {
        self.conflict = conflict
        self.decision = decision
        self.steps = steps
        self.reachedConflict = reachedConflict
        self.failure = failure
    }
}

public enum LRConflictBranchOutcome: Hashable, CustomStringConvertible {
    case accepted
    case rejected(String)
    case stepLimit(Int)

    public var description: String {
        switch self {
        case .accepted: "accepted"
        case .rejected(let reason): "rejected: \(reason)"
        case .stepLimit(let limit): "stopped after \(limit) steps"
        }
    }
}

/// Continuation produced by forcing one competing action at the conflict cell,
/// then following the generated table decisions.
public struct LRConflictBranchReplay {
    public let action: LRAction
    public let wasSelected: Bool
    public let steps: [LRConflictReplayStep]
    public let outcome: LRConflictBranchOutcome

    public init(action: LRAction, wasSelected: Bool, steps: [LRConflictReplayStep], outcome: LRConflictBranchOutcome) {
        self.action = action
        self.wasSelected = wasSelected
        self.steps = steps
        self.outcome = outcome
    }
}

public extension LRAutomaton {
    /// Replays the shortest witness using the generated ACTION decisions and
    /// stops immediately before the conflicted cell is executed.
    func replay(_ conflict: LRConflict, maximumSteps: Int = 10_000) -> LRConflictReplay {
        let decision = conflict.decision ?? actionDecisions[conflict.state]?[conflict.lookahead]
        var stack = [0]
        var tokenIndex = 0
        var steps: [LRConflictReplayStep] = []

        func reference(_ state: Int) -> LRTraceState {
            LRTraceState(index: state, identity: self.state(state)?.identity ?? LRArtifactID(rawValue: "state-index:\(state)"))
        }
        func result(_ reached: Bool, _ failure: String? = nil) -> LRConflictReplay {
            LRConflictReplay(conflict: conflict, decision: decision, steps: steps, reachedConflict: reached, failure: failure)
        }

        while steps.count < maximumSteps {
            guard let state = stack.last else { return result(false, "parser stack underflow") }
            let lookahead = tokenIndex < conflict.witness.count ? conflict.witness[tokenIndex] : Terminal.meta(.eof)
            let references = stack.map(reference)
            if state == conflict.state && lookahead == conflict.lookahead {
                steps.append(LRConflictReplayStep(index: steps.count, kind: .conflict, tokenIndex: tokenIndex, lookahead: lookahead, state: reference(state), stack: references, action: decision?.selectedAction))
                return result(true)
            }
            guard let action = actionDecisions[state]?[lookahead]?.selectedAction ?? actionTable[state]?[lookahead] else {
                return result(false, "no ACTION for state \(state) on \(lookahead)")
            }
            switch action {
            case .shift(let target):
                steps.append(LRConflictReplayStep(index: steps.count, kind: .shift, tokenIndex: tokenIndex, lookahead: lookahead, state: reference(state), stack: references, action: action))
                stack.append(target)
                tokenIndex += 1
            case .reduce(let production):
                steps.append(LRConflictReplayStep(index: steps.count, kind: .reduce, tokenIndex: tokenIndex, lookahead: lookahead, state: reference(state), stack: references, action: action))
                guard stack.count > production.rule.count else { return result(false, "stack underflow reducing by \(production)") }
                if !production.rule.isEmpty { stack.removeLast(production.rule.count) }
                guard let previous = stack.last, let target = gotoTable[previous]?[production.goal] else {
                    return result(false, "missing GOTO after reducing by \(production)")
                }
                stack.append(target)
            case .accept:
                steps.append(LRConflictReplayStep(index: steps.count, kind: .accept, tokenIndex: tokenIndex, lookahead: lookahead, state: reference(state), stack: references, action: action))
                return result(false, "the witness was accepted before reaching the conflict")
            }
        }
        return result(false, "replay exceeded \(maximumSteps) steps")
    }

    /// Reaches the conflict once, then forces each distinct competing action
    /// and continues with the generated table until acceptance or rejection.
    func replayBranches(_ conflict: LRConflict, maximumSteps: Int = 10_000) -> [LRConflictBranchReplay] {
        let prefix = replay(conflict, maximumSteps: maximumSteps)
        guard prefix.reachedConflict, let point = prefix.steps.last else { return [] }

        func reference(_ state: Int) -> LRTraceState {
            LRTraceState(index: state, identity: self.state(state)?.identity ?? LRArtifactID(rawValue: "state-index:\(state)"))
        }

        return conflict.actions.map { forcedAction in
            var stack = point.stack.map(\.index)
            var tokenIndex = point.tokenIndex
            var steps = prefix.steps

            func apply(_ action: LRAction) -> LRConflictBranchOutcome? {
                guard let state = stack.last else { return .rejected("parser stack underflow") }
                let lookahead = tokenIndex < conflict.witness.count ? conflict.witness[tokenIndex] : Terminal.meta(.eof)
                let kind: LRConflictReplayStep.Kind
                switch action {
                case .shift: kind = .shift
                case .reduce: kind = .reduce
                case .accept: kind = .accept
                }
                steps.append(LRConflictReplayStep(index: steps.count, kind: kind, tokenIndex: tokenIndex, lookahead: lookahead, state: reference(state), stack: stack.map(reference), action: action))
                switch action {
                case .shift(let target):
                    stack.append(target)
                    tokenIndex += 1
                    return nil
                case .reduce(let production):
                    guard stack.count > production.rule.count else { return .rejected("stack underflow reducing by \(production)") }
                    if !production.rule.isEmpty { stack.removeLast(production.rule.count) }
                    guard let previous = stack.last, let target = gotoTable[previous]?[production.goal] else {
                        return .rejected("missing GOTO after reducing by \(production)")
                    }
                    stack.append(target)
                    return nil
                case .accept:
                    return .accepted
                }
            }

            var outcome = apply(forcedAction)
            while outcome == nil, steps.count < maximumSteps {
                guard let state = stack.last else { outcome = .rejected("parser stack underflow"); break }
                let lookahead = tokenIndex < conflict.witness.count ? conflict.witness[tokenIndex] : Terminal.meta(.eof)
                guard let action = actionTable[state]?[lookahead] else {
                    outcome = .rejected("no ACTION for state \(state) on \(lookahead)")
                    break
                }
                outcome = apply(action)
            }
            return LRConflictBranchReplay(
                action: forcedAction,
                wasSelected: conflict.decision?.selectedAction == forcedAction,
                steps: steps,
                outcome: outcome ?? .stepLimit(maximumSteps)
            )
        }
    }
}
