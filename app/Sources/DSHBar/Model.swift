import Foundation

/// Agent states the menu bar icon can express.
enum BarState: String, CaseIterable {
    case idle
    case thinking
    case tool
    case approval
    case done
    case error

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .tool: return "Running a tool"
        case .approval: return "Waiting for approval"
        case .done: return "Done"
        case .error: return "Error"
        }
    }

    var animates: Bool {
        switch self {
        case .thinking, .tool: return true
        default: return false
        }
    }
}

/// Snapshot of what the menu bar shows. In M1 this is driven by a demo
/// sequencer; in M2 the host plugin will feed the same structure.
struct BarSnapshot {
    var state: BarState = .idle
    var title: String = "No active session"
    var detail: String = "Start a conversation in DSH"
    var model: String = ""
    var tokens: Int = 0
    var cost: String = "$0.00"
    var approvals: Int = 0

    static let demo: [BarSnapshot] = [
        BarSnapshot(state: .idle, title: "No active session", detail: "Waiting for DSH", model: "deepseek-flash"),
        BarSnapshot(state: .thinking, title: "Refactor the parser", detail: "Thinking…", model: "deepseek-flash", tokens: 12_480, cost: "$0.01"),
        BarSnapshot(state: .tool, title: "Refactor the parser", detail: "bash · npm test", model: "deepseek-flash", tokens: 18_920, cost: "$0.02"),
        BarSnapshot(state: .approval, title: "Refactor the parser", detail: "Approval: write src/parser.ts", model: "deepseek-flash", tokens: 21_310, cost: "$0.03", approvals: 1),
        BarSnapshot(state: .done, title: "Refactor the parser", detail: "Done · 34 s", model: "deepseek-flash", tokens: 24_010, cost: "$0.03"),
        BarSnapshot(state: .error, title: "Refactor the parser", detail: "Tool failed: npm test", model: "deepseek-flash", tokens: 24_800, cost: "$0.03"),
    ]
}
