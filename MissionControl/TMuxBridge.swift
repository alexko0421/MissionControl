import Foundation

// MARK: - TMuxBridge
// Thin wrapper around tmux CLI commands.
// All calls are synchronous — call from background if needed.

enum TMuxBridge {

    // Capture last N lines from a tmux pane and return as TerminalLines
    static func capturePane(target: String, lastLines: Int = 30) -> [TerminalLine] {
        let output = shell("tmux capture-pane -t \"\(target)\" -p -S -\(lastLines) 2>/dev/null")
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                let type = classifyLine(line)
                return TerminalLine(text: line, type: type)
            }
    }

    // Send a command string to a tmux pane
    static func sendKeys(target: String, command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        _ = shell("tmux send-keys -t \"\(target)\" \"\(escaped)\" Enter 2>/dev/null")
    }

    // List active tmux sessions
    static func listSessions() -> [String] {
        let output = shell("tmux ls -F '#{session_name}' 2>/dev/null")
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Private

    private static func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.arguments = ["-c", command]
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Heuristic: classify a terminal line by its content
    private static func classifyLine(_ line: String) -> TerminalLine.LineType {
        let l = line.lowercased()
        if l.hasPrefix("✓") || l.contains("success") || l.contains("passed") || l.contains("done") {
            return .success
        }
        if l.hasPrefix("⚠") || l.contains("warning") || l.contains("await") || l.contains("waiting") {
            return .warning
        }
        if l.hasPrefix("✗") || l.hasPrefix("error") || l.contains("failed") || l.contains("fatal") {
            return .error
        }
        return .normal
    }
}
