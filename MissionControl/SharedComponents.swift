import SwiftUI

// MARK: - Status Dot

struct StatusDot: View {
    let status: AgentStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status.hasPulse {
                Circle()
                    .fill(status.color.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .onAppear { if status.hasPulse { pulse = true } }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: AgentStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10))
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
