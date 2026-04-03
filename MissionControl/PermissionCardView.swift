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
                        .lineLimit(3)
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
        let oldLines = oldStr.isEmpty ? [] : oldStr.components(separatedBy: "\n")
        let newLines = newStr.isEmpty ? [] : newStr.components(separatedBy: "\n")

        if !oldLines.isEmpty || !newLines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(oldLines.prefix(6).enumerated()), id: \.offset) { _, line in
                    diffLine(text: line, isDeletion: true)
                }
                ForEach(Array(newLines.prefix(6).enumerated()), id: \.offset) { _, line in
                    diffLine(text: line, isDeletion: false)
                }
                if oldLines.count > 6 || newLines.count > 6 {
                    Text("  ...")
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

    private func diffLine(text: String, isDeletion: Bool) -> some View {
        let color = isDeletion
            ? Color(red: 0.90, green: 0.35, blue: 0.35)
            : Color(red: 0.30, green: 0.85, blue: 0.50)
        let bg = isDeletion
            ? Color(red: 0.35, green: 0.15, blue: 0.15).opacity(0.5)
            : Color(red: 0.15, green: 0.35, blue: 0.20).opacity(0.5)

        return HStack(spacing: 0) {
            Text(isDeletion ? "- " : "+ ")
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
