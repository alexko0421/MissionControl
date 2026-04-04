import Foundation

struct HookRouter {
    let source: String
    let event: String
    let hookInput: [String: Any]

    func route() {
        let agentId = deriveAgentId()
        let env = EnvCollector.collect()
        let app = EnvCollector.detectApp()
        let tmux = EnvCollector.detectTmux()
        let cwd = hookInput["cwd"] as? String ?? ""
        let name = EnvCollector.projectName(cwd: cwd)
        let tty = EnvCollector.tty()

        switch event.lowercased() {
        case "sessionstart":
            let msg = BridgeMessage(
                type: "session_start", agent_id: agentId, agent_type: source,
                name: name, status: "running", worktree: cwd, app: app,
                tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
                tmux_pane: tmux.session != nil ? tmux.pane : nil,
                event: event, terminal_env: env, tty: tty, cwd: cwd
            )
            _ = SocketClient.send(msg)

        case "sessionend":
            let msg = BridgeMessage(type: "session_end", agent_id: agentId, event: event)
            _ = SocketClient.send(msg)

        case "userpromptsubmit":
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId, agent_type: source,
                name: name, status: "running", task: "Processing...",
                worktree: cwd, app: app,
                tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
                tmux_pane: tmux.session != nil ? tmux.pane : nil,
                event: event, terminal_env: env, tty: tty, cwd: cwd
            )
            _ = SocketClient.send(msg)

        case "pretooluse":
            let toolName = hookInput["tool_name"] as? String ?? "tool"
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId,
                status: "running", task: "Using \(toolName)...",
                event: event, terminal_env: env
            )
            _ = SocketClient.send(msg)

        case "posttooluse":
            let clearMsg = BridgeMessage(type: "question_resolved", agent_id: agentId)
            _ = SocketClient.send(clearMsg)
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId, status: "running",
                event: event, terminal_env: env
            )
            _ = SocketClient.send(msg)

        case "notification":
            let notification = hookInput["message"] as? String ?? ""
            let msg = BridgeMessage(
                type: "notification", agent_id: agentId,
                summary: notification, event: event
            )
            _ = SocketClient.send(msg)

        case "stop":
            handleStop(agentId: agentId, name: name, cwd: cwd, app: app, tmux: tmux, env: env, tty: tty)

        case "subagentstart":
            let parentSessionId = hookInput["parent_session_id"] as? String
            let parentId = parentSessionId.map { String($0.prefix(8)) }
            let msg = BridgeMessage(
                type: "subagent_start", agent_id: agentId, agent_type: source,
                name: "Sub-agent", status: "running",
                worktree: cwd, app: app,
                event: event, terminal_env: env, subagent_parent_id: parentId, cwd: cwd
            )
            _ = SocketClient.send(msg)

        case "subagentstop":
            let msg = BridgeMessage(type: "subagent_stop", agent_id: agentId, event: event)
            _ = SocketClient.send(msg)

        case "precompact":
            let msg = BridgeMessage(type: "pre_compact", agent_id: agentId, event: event)
            _ = SocketClient.send(msg)

        case "permissionrequest":
            handlePermission(agentId: agentId, tmux: tmux, env: env, name: name)

        default:
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId,
                event: event, terminal_env: env
            )
            _ = SocketClient.send(msg)
        }
    }

    private func deriveAgentId() -> String {
        let sessionId = hookInput["session_id"] as? String ?? ""
        if !sessionId.isEmpty {
            return String(sessionId.prefix(8))
        }
        let cwd = hookInput["cwd"] as? String ?? ""
        let data = Data(cwd.utf8)
        var hash: UInt64 = 5381
        for byte in data { hash = hash &* 33 &+ UInt64(byte) }
        return String(format: "%08x", UInt32(hash & 0xFFFFFFFF))
    }

    private func handleStop(agentId: String, name: String, cwd: String, app: String,
                            tmux: (session: String?, window: Int, pane: Int),
                            env: [String: String], tty: String?) {
        let lastMessage = hookInput["last_assistant_message"] as? String ?? ""
        let stopReason = hookInput["stop_reason"] as? String ?? ""

        var status = "running"
        let msgLower = lastMessage.lowercased()
        let questionSignals = ["?", "\u{FF1F}", "which option", "do you want", "should i",
                               "please choose", "\u{4F60}\u{60F3}", "\u{4F60}\u{89C9}\u{5F97}", "\u{8BF7}\u{9009}\u{62E9}", "\u{4F60}\u{9078}"]
        if questionSignals.contains(where: { msgLower.contains($0) }) {
            status = "blocked"
        }
        if stopReason == "tool_use" { status = "blocked" }
        if msgLower.contains("done") || msgLower.contains("complete") || msgLower.contains("\u{5B8C}\u{6210}") {
            status = "done"
        }

        let lines = lastMessage.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count > 5 }
        let task = String((lines.first ?? "Working...").prefix(60))
        let summary = String(lines.prefix(3).joined(separator: " ").prefix(300))
        let nextAction = String((lines.last ?? "").prefix(200))

        let msg = BridgeMessage(
            type: "status_update", agent_id: agentId, agent_type: source,
            name: name, status: status, task: task, summary: summary,
            next_action: nextAction, worktree: cwd, app: app,
            tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
            tmux_pane: tmux.session != nil ? tmux.pane : nil,
            event: "Stop", terminal_env: env, tty: tty, cwd: cwd
        )
        _ = SocketClient.send(msg)
    }

    private func handlePermission(agentId: String,
                                  tmux: (session: String?, window: Int, pane: Int),
                                  env: [String: String], name: String) {
        let toolName = hookInput["tool_name"] as? String ?? "Unknown"
        var toolInput: [String: String] = [:]
        if let raw = hookInput["tool_input"] as? [String: Any] {
            for (k, v) in raw {
                toolInput[k] = v as? String ?? "\(v)"
            }
        }
        let requestId = "perm_\(UUID().uuidString.prefix(12))"

        let msg = BridgeMessage(
            type: "permission_request", agent_id: agentId,
            name: name, app: EnvCollector.detectApp(),
            tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
            tmux_pane: tmux.session != nil ? tmux.pane : nil,
            request_id: requestId, tool: toolName, tool_input: toolInput,
            terminal_env: env
        )

        let response = SocketClient.send(msg, waitForResponse: true, timeout: 86400)
        if let response = response, response.decision == "deny" {
            let output = ["decision": "block", "reason": "User denied in MissionControl"]
            if let data = try? JSONSerialization.data(withJSONObject: output),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("{\"approve\":true}")
        }
    }
}
