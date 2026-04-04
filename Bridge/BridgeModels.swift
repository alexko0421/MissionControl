import Foundation

struct BridgeMessage: Codable {
    var type: String
    var agent_id: String?
    var agent_type: String?
    var name: String?
    var status: String?
    var task: String?
    var summary: String?
    var next_action: String?
    var worktree: String?
    var app: String?
    var tmux_session: String?
    var tmux_window: Int?
    var tmux_pane: Int?
    var request_id: String?
    var tool: String?
    var tool_input: [String: String]?
    var markdown: String?
    var question: String?
    var options: [[String: String]]?
    var event: String?
    var terminal_env: [String: String]?
    var subagent_parent_id: String?
    var tty: String?
    var cwd: String?
}

struct BridgeResponse: Codable {
    var type: String?
    var request_id: String?
    var decision: String?
    var answer: String?
    var reason: String?
}
