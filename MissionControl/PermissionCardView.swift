import SwiftUI

struct PermissionCardView: View {
    let agent: Agent
    let permission: PermissionRequest
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: warning icon + tool name
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Text(permission.tool)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(agent.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // File path header (like Vibe Island: "/path/to/file  -10")
            if let filePath = permission.toolInput["file_path"], !filePath.isEmpty {
                HStack(spacing: 4) {
                    Text(shortenPath(filePath))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    if !diffLines.isEmpty {
                        let adds = diffLines.filter { $0.type == .addition }.count
                        let dels = diffLines.filter { $0.type == .deletion }.count
                        if dels > 0 {
                            Text("-\(dels)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.90, green: 0.35, blue: 0.35))
                        }
                        if adds > 0 {
                            Text("+\(adds)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.30, green: 0.85, blue: 0.50))
                        }
                    }
                    Spacer()
                }
            }

            // Command display (for Bash tool)
            if let command = permission.toolInput["command"], !command.isEmpty {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(command)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let desc = permission.toolInput["description"], !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

            // Diff preview (unified diff with line numbers)
            if !diffLines.isEmpty {
                DiffPreviewView(lines: diffLines)
            }

            // Four buttons: Deny / Allow Once / Always Allow / Bypass
            HStack(spacing: 6) {
                PermButton(label: "Deny", color: Color(red: 0.25, green: 0.25, blue: 0.28)) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .deny)
                }
                PermButton(label: "Allow Once", color: Color(red: 0.30, green: 0.30, blue: 0.33)) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .allowOnce)
                }
                PermButton(label: "Always Allow", color: Color(red: 0.30, green: 0.42, blue: 0.58)) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .alwaysAllow)
                }
                PermButton(label: "Bypass", color: Color(red: 0.65, green: 0.35, blue: 0.20)) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .bypass)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.937, green: 0.624, blue: 0.153).opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
    }

    // MARK: - Smart Diff

    private var diffLines: [DiffLine] {
        let tool = permission.tool.lowercased()

        if tool.contains("edit") {
            return computeEditDiff()
        } else if tool.contains("write") {
            return computeWriteDiff()
        }
        return []
    }

    /// Compute a unified diff between old_string and new_string.
    /// Only marks lines that actually changed; shared lines show as context.
    private func computeEditDiff() -> [DiffLine] {
        guard let oldStr = permission.toolInput["old_string"], !oldStr.isEmpty,
              let newStr = permission.toolInput["new_string"], !newStr.isEmpty else { return [] }

        let oldLines = oldStr.components(separatedBy: "\n")
        let newLines = newStr.components(separatedBy: "\n")

        // Simple LCS-based diff
        let diff = computeLCS(old: oldLines, new: newLines)

        // Limit to ~15 lines for the card
        let limited = Array(diff.prefix(15))
        var result = limited
        if diff.count > 15 {
            let remaining = diff.count - 15
            result.append(DiffLine(text: "... \(remaining) more lines", type: .context, lineNum: nil))
        }
        return result
    }

    private func computeWriteDiff() -> [DiffLine] {
        guard let content = permission.toolInput["content"], !content.isEmpty else { return [] }
        let lines = content.components(separatedBy: "\n")
        var result: [DiffLine] = []
        for (i, line) in lines.prefix(12).enumerated() {
            result.append(DiffLine(text: line, type: .addition, lineNum: i + 1))
        }
        if lines.count > 12 {
            result.append(DiffLine(text: "... +\(lines.count - 12) more lines", type: .context, lineNum: nil))
        }
        return result
    }

    /// Simple LCS diff: produces unified diff lines with context, deletions, additions
    private func computeLCS(old: [String], new: [String]) -> [DiffLine] {
        let m = old.count, n = new.count

        // Build LCS table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) {
            for j in 1...max(n, 1) {
                if i <= m && j <= n && old[i-1] == new[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else if i <= m && j <= n {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }

        // Backtrack to produce diff
        var result: [DiffLine] = []
        var i = m, j = n
        var stack: [DiffLine] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i-1] == new[j-1] {
                stack.append(DiffLine(text: old[i-1], type: .context, lineNum: i))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                stack.append(DiffLine(text: new[j-1], type: .addition, lineNum: j))
                j -= 1
            } else if i > 0 {
                stack.append(DiffLine(text: old[i-1], type: .deletion, lineNum: i))
                i -= 1
            }
        }

        result = stack.reversed()

        // Trim leading/trailing context — show max 1 context line around changes
        return trimContext(result)
    }

    /// Keep only context lines adjacent to changes (max 1 line of context on each side)
    private func trimContext(_ lines: [DiffLine]) -> [DiffLine] {
        guard !lines.isEmpty else { return [] }

        // Mark which lines are "near" a change
        var nearChange = Array(repeating: false, count: lines.count)
        for (i, line) in lines.enumerated() {
            if line.type != .context {
                // Mark this line and 1 neighbor on each side
                for offset in -1...1 {
                    let idx = i + offset
                    if idx >= 0 && idx < lines.count { nearChange[idx] = true }
                }
            }
        }

        var result: [DiffLine] = []
        var skipping = false
        for (i, line) in lines.enumerated() {
            if nearChange[i] {
                if skipping {
                    result.append(DiffLine(text: "···", type: .context, lineNum: nil))
                    skipping = false
                }
                result.append(line)
            } else {
                skipping = true
            }
        }
        return result
    }

    private var toolIcon: String {
        let t = permission.tool.lowercased()
        if t.contains("bash") { return "terminal" }
        if t.contains("edit") { return "pencil.line" }
        if t.contains("write") { return "doc.badge.plus" }
        if t.contains("read") { return "doc.text" }
        if t.contains("glob") || t.contains("grep") { return "magnifyingglass" }
        return "lock.shield.fill"
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Diff Types

struct DiffLine: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType
    var lineNum: Int?

    enum DiffType {
        case addition, deletion, context
    }
}

// MARK: - Diff Preview (Unified diff with line numbers)

struct DiffPreviewView: View {
    let lines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                HStack(spacing: 0) {
                    // Line number
                    Text(line.lineNum != nil ? "\(line.lineNum!)" : " ")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(width: 24, alignment: .trailing)
                        .padding(.trailing, 4)

                    // +/- prefix
                    Text(prefix(for: line.type))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(lineColor(line.type).opacity(0.7))
                        .frame(width: 12, alignment: .leading)

                    // Content
                    Text(line.text)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(lineColor(line.type))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(lineBg(line.type))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func prefix(for type: DiffLine.DiffType) -> String {
        switch type {
        case .addition: return "+"
        case .deletion: return "-"
        case .context:  return " "
        }
    }

    private func lineColor(_ type: DiffLine.DiffType) -> Color {
        switch type {
        case .addition: return Color(red: 0.30, green: 0.85, blue: 0.50)
        case .deletion: return Color(red: 0.90, green: 0.35, blue: 0.35)
        case .context:  return .white.opacity(0.5)
        }
    }

    private func lineBg(_ type: DiffLine.DiffType) -> Color {
        switch type {
        case .addition: return Color(red: 0.15, green: 0.35, blue: 0.20).opacity(0.5)
        case .deletion: return Color(red: 0.35, green: 0.15, blue: 0.15).opacity(0.5)
        case .context:  return Color.clear
        }
    }
}

// MARK: - Permission Button

struct PermButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(color.opacity(isHovered ? 1.0 : 0.85))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
