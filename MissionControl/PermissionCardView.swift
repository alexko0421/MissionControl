import SwiftUI

struct PermissionCardView: View {
    let agent: Agent
    let permission: PermissionRequest
    @EnvironmentObject var store: AgentStore
    @State private var isApproveHovered = false
    @State private var isDenyHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Text("Permission Request")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Spacer()
            }

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

            HStack(spacing: 8) {
                Button(action: {
                    store.approvePermission(agentId: agent.id, requestId: permission.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Approve")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.204, green: 0.827, blue: 0.600).opacity(isApproveHovered ? 1.0 : 0.85))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .onHover { isApproveHovered = $0 }

                Button(action: {
                    store.denyPermission(agentId: agent.id, requestId: permission.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Deny")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.937, green: 0.267, blue: 0.267).opacity(isDenyHovered ? 1.0 : 0.85))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .onHover { isDenyHovered = $0 }
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
