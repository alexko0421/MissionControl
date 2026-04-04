import Foundation

// MARK: - Incoming Messages (Agent → App)

enum IncomingMessageType: String, Codable {
    case statusUpdate = "status_update"
    case permissionRequest = "permission_request"
    case planReview = "plan_review"
    case question = "question"
    case questionResolved = "question_resolved"
}

struct IncomingMessage: Codable {
    let type: IncomingMessageType

    var agentId: String?
    var agentType: String?
    var name: String?
    var status: String?
    var task: String?
    var summary: String?
    var nextAction: String?
    var worktree: String?
    var app: String?
    var tmuxSession: String?
    var tmuxWindow: Int?
    var tmuxPane: Int?

    var requestId: String?
    var tool: String?
    var toolInput: [String: String]?

    var markdown: String?

    // question fields
    var question: String?
    var options: [[String: String]]?

    // New fields for Vibe Island parity
    var event: String?
    var terminalEnv: TerminalEnv?
    var subagentParentId: String?
    var tty: String?
    var cwd: String?

    enum CodingKeys: String, CodingKey {
        case type
        case agentId = "agent_id"
        case agentType = "agent_type"
        case name, status, task, summary
        case nextAction = "next_action"
        case worktree, app
        case tmuxSession = "tmux_session"
        case tmuxWindow = "tmux_window"
        case tmuxPane = "tmux_pane"
        case requestId = "request_id"
        case tool
        case toolInput = "tool_input"
        case markdown
        case question, options
        case event
        case terminalEnv = "terminal_env"
        case subagentParentId = "subagent_parent_id"
        case tty, cwd
    }
}

// MARK: - Outgoing Messages (App → Agent)

struct OutgoingMessage: Codable {
    let type: String
    let requestId: String
    let decision: String

    enum CodingKeys: String, CodingKey {
        case type
        case requestId = "request_id"
        case decision
    }
}
