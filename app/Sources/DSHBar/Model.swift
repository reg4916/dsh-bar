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

struct BarApprovalItem: Identifiable {
    let id: String
    let toolName: String
    let reason: String?
}

/// One option of an ask_user_question prompt. The value sent back is the label.
struct BarOption: Decodable {
    let label: String
    let description: String?
}

/// One question of a held ask. Mirrors the DSH user-questions payload.
struct BarQuestion: Decodable {
    let id: String
    let question: String
    let detail: String?
    let header: String?
    let options: [BarOption]?
    let multiSelect: Bool?
}

/// A whole ask: its held id plus every question it carries.
struct BarQuestionGroup: Decodable, Identifiable {
    let id: String
    let sessionId: String?
    let title: String?
    let questions: [BarQuestion]
}

/// Compact row for the session picker, built from status.rows.
struct BarSession: Identifiable {
    let id: String
    let title: String
    let state: BarState
    let busy: Bool
    let waiting: Bool
}

/// Snapshot of what the menu bar shows.
struct BarSnapshot {
    var state: BarState = .idle
    var title: String = "No active session"
    var detail: String = "Start a conversation in DSH"
    var model: String = ""
    var tokens: Int = 0
    var cost: String = "—"
    var approvals: Int = 0
    var approvalItems: [BarApprovalItem] = []
    var questionCount: Int = 0
    var activeSessionId: String? = nil
    var busy: Bool = false
    var questionGroups: [BarQuestionGroup] = []
    var sessions: [BarSession] = []

    static let demo: [BarSnapshot] = [
        BarSnapshot(state: .idle, title: "No active session", detail: "Waiting for DSH", model: "deepseek-flash"),
        BarSnapshot(state: .thinking, title: "Refactor the parser", detail: "Thinking…", model: "deepseek-flash", tokens: 12_480),
        BarSnapshot(state: .tool, title: "Refactor the parser", detail: "bash · npm test", model: "deepseek-flash", tokens: 18_920),
        BarSnapshot(state: .approval, title: "Refactor the parser", detail: "Approval: write src/parser.ts", model: "deepseek-flash", tokens: 21_310, approvals: 1, approvalItems: [BarApprovalItem(id: "demo", toolName: "bash", reason: "write src/parser.ts")], questionCount: 0, activeSessionId: "demo", busy: true),
        BarSnapshot(state: .done, title: "Refactor the parser", detail: "Done · 34 s", model: "deepseek-flash", tokens: 24_010),
        BarSnapshot(state: .error, title: "Refactor the parser", detail: "Tool failed: npm test", model: "deepseek-flash", tokens: 24_800),
    ]
}
