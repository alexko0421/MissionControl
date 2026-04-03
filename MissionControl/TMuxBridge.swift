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
    /// Detects: numbered options, y/n, arrow-select, diff approval, free-text input.
    static func detectPrompt(target: String) -> AgentQuestion? {
        let output = shell("tmux capture-pane -t \"\(target)\" -p -S -30 2>/dev/null")
        let allLines = output.components(separatedBy: "\n")
        let lines = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        let id = "\(target)-\(Int(Date().timeIntervalSince1970))"

        // === 1. Numbered options: "1. Yes" / "› 1. Yes" ===
        if let result = detectNumberedOptions(lines: lines, id: id) { return result }

        // === 2. Arrow-key selection: lines with › cursor, no numbers ===
        if let result = detectArrowSelect(lines: lines, id: id) { return result }

        // === 3. Diff approval: diff markers + approve prompt ===
        if let result = detectDiffPrompt(lines: lines, id: id) { return result }

        // === 4. Y/N prompt: "(y/n)", "[Y/n]", etc. ===
        if let result = detectYesNo(lines: lines, id: id) { return result }

        // === 5. Free-text input: question + input indicator ===
        if let result = detectFreeInput(lines: lines, id: id) { return result }

        return nil
    }

    // MARK: - Prompt Type Detectors

    private static func detectNumberedOptions(lines: [String], id: String) -> AgentQuestion? {
        var options: [(number: Int, label: String, highlighted: Bool)] = []
        var questionLine: String? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHighlighted = trimmed.hasPrefix("›") || trimmed.hasPrefix(">")
            let cleaned = trimmed
                .replacingOccurrences(of: "^[›>]\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if cleaned.range(of: #"^(\d+)[.\)]\s+(.+)"#, options: .regularExpression) != nil {
                let numStr = String(cleaned.prefix(while: { $0.isNumber }))
                if let num = Int(numStr), let spaceIdx = cleaned.firstIndex(of: " ") {
                    let label = String(cleaned[cleaned.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
                    options.append((number: num, label: label, highlighted: isHighlighted))

                    if options.count == 1 && i > 0 {
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

        guard !options.isEmpty else { return nil }
        return AgentQuestion(
            id: id,
            question: questionLine ?? "Choose an option",
            options: options.map { .init(id: $0.number, label: $0.label, sendKey: "\($0.number)", isHighlighted: $0.highlighted) },
            promptType: .numbered,
            detectedAt: Date()
        )
    }

    private static func detectArrowSelect(lines: [String], id: String) -> AgentQuestion? {
        // Look for a block of lines where one has › prefix (cursor) and others are list items
        var items: [(label: String, highlighted: Bool)] = []
        var questionLine: String? = nil
        var inList = false

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHighlighted = trimmed.hasPrefix("›") || trimmed.hasPrefix(">")

            if isHighlighted {
                let label = trimmed
                    .replacingOccurrences(of: "^[›>]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !label.isEmpty && label.count > 1 {
                    items.append((label: label, highlighted: true))
                    inList = true
                    // Find question before the list
                    if questionLine == nil {
                        for j in stride(from: i - 1, through: max(0, i - 5), by: -1) {
                            let q = lines[j].trimmingCharacters(in: .whitespaces)
                            if !q.isEmpty && !q.hasPrefix("›") && !q.hasPrefix(">") && !q.hasPrefix("  ") {
                                questionLine = q
                                break
                            }
                        }
                    }
                }
            } else if inList {
                // Items near the highlighted one are also part of the list
                let label = trimmed.trimmingCharacters(in: .whitespaces)
                if !label.isEmpty && label.count > 1 &&
                   !label.contains("Esc to cancel") && !label.contains("esc to interrupt") {
                    items.append((label: label, highlighted: false))
                }
            }
        }

        // Need at least a highlighted item + 1 other to be a real arrow selection
        guard items.count >= 2, items.contains(where: { $0.highlighted }) else { return nil }

        // For arrow-select, each option sends arrow keys to navigate then Enter
        let highlightedIdx = items.firstIndex(where: { $0.highlighted }) ?? 0
        let options = items.enumerated().map { (idx, item) -> AgentQuestion.QuestionOption in
            // Calculate how many arrow keys needed relative to highlighted position
            let delta = idx - highlightedIdx
            var sendKey = ""
            if delta < 0 {
                sendKey = String(repeating: "Up ", count: abs(delta)) + "Enter"
            } else if delta > 0 {
                sendKey = String(repeating: "Down ", count: delta) + "Enter"
            } else {
                sendKey = "Enter"  // already highlighted
            }
            return .init(id: idx + 1, label: item.label, sendKey: sendKey, isHighlighted: item.highlighted)
        }

        return AgentQuestion(
            id: id,
            question: questionLine ?? "Select an option",
            options: options,
            promptType: .arrowSelect,
            detectedAt: Date()
        )
    }

    private static func detectDiffPrompt(lines: [String], id: String) -> AgentQuestion? {
        // Look for diff markers (+/-/@@) followed by an approval prompt
        var hasDiff = false
        var diffLines: [String] = []
        var promptLine: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@@") || trimmed.hasPrefix("+") || trimmed.hasPrefix("-") ||
               trimmed.hasPrefix("diff --") || trimmed.hasPrefix("index ") {
                hasDiff = true
                diffLines.append(line)
            }
            // Check for approval patterns after diff
            if hasDiff {
                let lower = trimmed.lowercased()
                if lower.contains("apply") || lower.contains("approve") || lower.contains("accept") ||
                   lower.contains("reject") || lower.contains("save") ||
                   (lower.contains("y/n") || lower.contains("[y]") || lower.contains("[n]")) {
                    promptLine = trimmed
                }
            }
        }

        guard hasDiff, promptLine != nil else { return nil }

        let diffPreview = diffLines.suffix(10).joined(separator: "\n")
        return AgentQuestion(
            id: id,
            question: promptLine ?? "Apply changes?",
            options: [
                .init(id: 1, label: "Yes, apply", sendKey: "y", isHighlighted: false),
                .init(id: 2, label: "No, reject", sendKey: "n", isHighlighted: false),
            ],
            promptType: .diff,
            diffContext: diffPreview,
            detectedAt: Date()
        )
    }

    private static func detectYesNo(lines: [String], id: String) -> AgentQuestion? {
        let lastLines = lines.suffix(5)
        for line in lastLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Match patterns: (y/n), [y/n], [Y/n], (yes/no), y/N, etc.
            if lower.range(of: #"\(y/?n\)|\[y/?n\]|\(yes/?no\)|\[yes/?no\]|y/n"#, options: .regularExpression) != nil {
                // Extract the question (everything before the y/n part)
                let question = trimmed
                    .replacingOccurrences(of: #"\s*[\(\[](y/?n|yes/?no)[\)\]].*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                return AgentQuestion(
                    id: id,
                    question: question.isEmpty ? trimmed : question,
                    options: [
                        .init(id: 1, label: "Yes", sendKey: "y", isHighlighted: false),
                        .init(id: 2, label: "No", sendKey: "n", isHighlighted: false),
                    ],
                    promptType: .yesNo,
                    detectedAt: Date()
                )
            }

            // Match: "Continue?" "Retry?" "Proceed?" at end of line
            if (lower.hasSuffix("continue?") || lower.hasSuffix("retry?") || lower.hasSuffix("proceed?")) {
                return AgentQuestion(
                    id: id,
                    question: trimmed,
                    options: [
                        .init(id: 1, label: "Yes", sendKey: "y", isHighlighted: false),
                        .init(id: 2, label: "No", sendKey: "n", isHighlighted: false),
                    ],
                    promptType: .yesNo,
                    detectedAt: Date()
                )
            }
        }
        return nil
    }

    private static func detectFreeInput(lines: [String], id: String) -> AgentQuestion? {
        let lastLines = lines.suffix(8)
        var detectedQuestion: String? = nil

        for line in lastLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("?") || trimmed.hasSuffix("？") ||
               trimmed.hasSuffix("呢") || trimmed.hasSuffix("吗") || trimmed.hasSuffix("嗎") {
                detectedQuestion = trimmed
            }
        }

        let hasInputIndicator = lastLines.contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t == "❯" || t == ">" || t == "›" ||
                   t.contains("Esc to cancel") || t.contains("esc to interrupt") ||
                   t.contains("Tab to amend")
        }

        guard let question = detectedQuestion, hasInputIndicator else { return nil }

        return AgentQuestion(
            id: id,
            question: question,
            options: [],
            promptType: .freeInput,
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
