import SwiftUI

struct PermissionCardView: View {
    let agent: Agent
    let permission: PermissionRequest
    @EnvironmentObject var store: AgentStore
    @State private var hoveredOption: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Text("Permission Request")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Spacer()
            }

            // Tool info
            VStack(alignment: .leading, spacing: 4) {
                Text("Tool: \(permission.tool)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                if let command = permission.toolInput["command"], !command.isEmpty {
                    Text(command)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .lineLimit(3)
                } else if let desc = permission.toolInput["description"], !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }
            }

            // Three real options matching Claude Code's permission prompt
            VStack(spacing: 6) {
                // Option 1: Yes
                PermissionOptionButton(
                    number: 1,
                    label: "Yes",
                    color: Color(red: 0.204, green: 0.827, blue: 0.600),
                    textColor: .black,
                    isHovered: hoveredOption == 1
                ) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .yes)
                }
                .onHover { hoveredOption = $0 ? 1 : nil }

                // Option 2: Yes, and don't ask again
                PermissionOptionButton(
                    number: 2,
                    label: "Yes, don't ask again",
                    color: Color(red: 0.365, green: 0.631, blue: 0.847),
                    textColor: .white,
                    isHovered: hoveredOption == 2
                ) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .yesDontAskAgain)
                }
                .onHover { hoveredOption = $0 ? 2 : nil }

                // Option 3: No
                PermissionOptionButton(
                    number: 3,
                    label: "No",
                    color: Color(red: 0.937, green: 0.267, blue: 0.267),
                    textColor: .white,
                    isHovered: hoveredOption == 3
                ) {
                    store.respondPermission(agentId: agent.id, requestId: permission.id, choice: .no)
                }
                .onHover { hoveredOption = $0 ? 3 : nil }
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
}

// MARK: - Option Button

struct PermissionOptionButton: View {
    let number: Int
    let label: String
    let color: Color
    let textColor: Color
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(textColor == .black ? Color.black.opacity(0.15) : Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(color.opacity(isHovered ? 1.0 : 0.85))
            .foregroundStyle(textColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
