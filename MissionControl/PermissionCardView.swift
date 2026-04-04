import SwiftUI

struct PermissionCardView: View {
    let agent: Agent
    let permission: PermissionRequest
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
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

            // File path
            if let filePath = permission.toolInput["file_path"], !filePath.isEmpty {
                Text(shortenPath(filePath))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Command (Bash)
            if let command = permission.toolInput["command"], !command.isEmpty {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(command)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(8)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Diff preview (Edit tool)
            if permission.tool.lowercased().contains("edit") {
                diffPreview
            }

            // Two buttons
            HStack(spacing: 8) {
                Button(action: { store.respondPermission(agentId: agent.id, allow: false) }) {
                    Text("Deny")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.25, green: 0.25, blue: 0.28))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: { store.respondPermission(agentId: agent.id, allow: true) }) {
                    Text("Allow")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.204, green: 0.827, blue: 0.600))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
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

    @ViewBuilder
    private var diffPreview: some View {
        let oldStr = permission.toolInput["old_string"] ?? ""
        let newStr = permission.toolInput["new_string"] ?? ""
        let unifiedLines = computeUnifiedDiff(oldStr: oldStr, newStr: newStr)

        if !unifiedLines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(unifiedLines.prefix(12).enumerated()), id: \.offset) { _, entry in
                    diffLine(text: entry.text, type: entry.type)
                }
                if unifiedLines.count > 12 {
                    Text("  ··· \(unifiedLines.count - 12) more lines")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private enum DiffLineType {
        case context, deletion, addition
    }

    private struct DiffEntry {
        let text: String
        let type: DiffLineType
    }

    /// Compute unified diff: show only changed lines with 1 line of context
    private func computeUnifiedDiff(oldStr: String, newStr: String) -> [DiffEntry] {
        let oldLines = oldStr.components(separatedBy: "\n")
        let newLines = newStr.components(separatedBy: "\n")

        // Simple LCS-based diff
        let lcs = longestCommonSubsequence(oldLines, newLines)
        var result: [DiffEntry] = []
        var oi = 0, ni = 0, li = 0

        while oi < oldLines.count || ni < newLines.count {
            if li < lcs.count, oi < oldLines.count, ni < newLines.count,
               oldLines[oi] == lcs[li], newLines[ni] == lcs[li] {
                // Common line — show as context
                result.append(DiffEntry(text: oldLines[oi], type: .context))
                oi += 1; ni += 1; li += 1
            } else {
                // Consume deletions (old lines not in LCS at this point)
                while oi < oldLines.count && (li >= lcs.count || oldLines[oi] != lcs[li]) {
                    result.append(DiffEntry(text: oldLines[oi], type: .deletion))
                    oi += 1
                }
                // Consume additions (new lines not in LCS at this point)
                while ni < newLines.count && (li >= lcs.count || newLines[ni] != lcs[li]) {
                    result.append(DiffEntry(text: newLines[ni], type: .addition))
                    ni += 1
                }
            }
        }

        // Trim: only show changed lines with 1 line of context around them
        return trimToContext(result, contextLines: 1)
    }

    /// Keep only changed lines plus N context lines around them
    private func trimToContext(_ entries: [DiffEntry], contextLines: Int) -> [DiffEntry] {
        guard !entries.isEmpty else { return [] }

        // Mark which lines are "interesting" (changed or near changed)
        var keep = [Bool](repeating: false, count: entries.count)
        for (i, entry) in entries.enumerated() {
            if entry.type != .context {
                // Mark this line and surrounding context
                let start = max(0, i - contextLines)
                let end = min(entries.count - 1, i + contextLines)
                for j in start...end { keep[j] = true }
            }
        }

        var result: [DiffEntry] = []
        var lastKept = false
        for (i, entry) in entries.enumerated() {
            if keep[i] {
                if !lastKept && !result.isEmpty {
                    result.append(DiffEntry(text: "···", type: .context))
                }
                result.append(entry)
                lastKept = true
            } else {
                lastKept = false
            }
        }
        return result
    }

    /// Simple LCS for string arrays
    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) {
            for j in 1...max(n, 1) {
                guard i <= m, j <= n else { continue }
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        // Backtrack
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    private func diffLine(text: String, type: DiffLineType) -> some View {
        let (prefix, color, bg): (String, Color, Color) = {
            switch type {
            case .deletion:
                return ("- ",
                        Color(red: 0.90, green: 0.35, blue: 0.35),
                        Color(red: 0.35, green: 0.15, blue: 0.15).opacity(0.5))
            case .addition:
                return ("+ ",
                        Color(red: 0.30, green: 0.85, blue: 0.50),
                        Color(red: 0.15, green: 0.35, blue: 0.20).opacity(0.5))
            case .context:
                return ("  ",
                        .white.opacity(0.4),
                        Color.clear)
            }
        }()

        return HStack(spacing: 0) {
            Text(prefix)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
