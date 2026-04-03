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

    // MARK: - Prompt Detection

    /// Parse the last N lines of a tmux pane looking for interactive prompts.
    /// Returns an AgentQuestion if a prompt with numbered options is detected.
    static func detectPrompt(target: String) -> AgentQuestion? {
        let output = shell("tmux capture-pane -t \"\(target)\" -p -S -20 2>/dev/null")
        let allLines = output.components(separatedBy: "\n")
        let lines = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        // Look for numbered options pattern: "  1. Some text" or "> 1. Some text"
        var options: [(number: Int, label: String, highlighted: Bool)] = []
        var questionLine: String? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match patterns like "› 1. Yes" or "  1. Yes" or "> 1. Yes"
            // The › character indicates the currently highlighted option
            let isHighlighted = trimmed.hasPrefix("›") || trimmed.hasPrefix(">")
            let cleaned = trimmed
                .replacingOccurrences(of: "^[›>]\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            // Match "N. text" or "N) text"
            if let match = cleaned.range(of: #"^(\d+)[.\)]\s+(.+)"#, options: .regularExpression) {
                let numStr = String(cleaned[cleaned.startIndex..<cleaned.index(cleaned.startIndex, offsetBy: 1)])
                if let num = Int(numStr) {
                    let labelStart = cleaned.index(after: cleaned.firstIndex(of: " ")!)
                    let label = String(cleaned[labelStart...]).trimmingCharacters(in: .whitespaces)
                    options.append((number: num, label: label, highlighted: isHighlighted))

                    // The question is usually 1-2 lines before the first option
                    if options.count == 1 && i > 0 {
                        // Look backwards for the question text
                        for j in stride(from: i - 1, through: max(0, i - 3), by: -1) {
                            let q = lines[j].trimmingCharacters(in: .whitespaces)
                            if !q.isEmpty && q.range(of: #"^\d+[.\)]"#, options: .regularExpression) == nil {
                                questionLine = q
                                break
                            }
                        }
                    }
                }
            }
        }

        // Also check for simple "? question [y/n]" or "Do you want to proceed?" patterns
        if options.isEmpty {
            for line in lines.suffix(5) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // "Esc to cancel" is a Claude Code prompt indicator
                if trimmed.contains("Esc to cancel") {
                    // This is a Claude Code interactive prompt — but options were already parsed above
                    // If no numbered options found, it might be a yes/no style
                    break
                }
            }
        }

        guard !options.isEmpty else { return nil }

        let question = questionLine ?? "Choose an option"
        let agentOptions = options.map { opt in
            AgentQuestion.QuestionOption(
                id: opt.number,
                label: opt.label,
                isHighlighted: opt.highlighted
            )
        }

        return AgentQuestion(
            id: "\(target)-\(Int(Date().timeIntervalSince1970))",
            question: question,
            options: agentOptions,
            detectedAt: Date()
        )
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
