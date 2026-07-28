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
}
