import SwiftUI

// MARK: - Status Dot

struct StatusDot: View {
    let status: AgentStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status.hasPulse {
                Circle()
                    .fill(status.color.opacity(0.4))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
            }
            
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .frame(width: 14, height: 14)
        .onAppear { 
            if status.hasPulse {
                withAnimation { pulse = true }
            }
        }
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

// MARK: - Alert Pulse Modifier

struct AlertPulseModifier: ViewModifier {
    let isActive: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Capsule()
                    .stroke(Color(red: 0.937, green: 0.624, blue: 0.153), lineWidth: 2)
                    .opacity(pulse ? 0.85 : 0)
                    .padding(-1)
            )
            .onChange(of: isActive) { newValue in
                if newValue {
                    // Simple repeating flash: on/off
                    startFlashing()
                } else {
                    pulse = false
                }
            }
    }

    private func startFlashing() {
        var count = 0
        func flash() {
            guard count < 8 else {
                withAnimation(.easeOut(duration: 0.2)) { pulse = false }
                return
            }
            let isOn = count % 2 == 0
            withAnimation(.easeInOut(duration: 0.35)) {
                pulse = isOn
            }
            count += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                flash()
            }
        }
        flash()
    }
}

extension View {
    func alertPulse(isActive: Bool) -> some View {
        modifier(AlertPulseModifier(isActive: isActive))
    }
}
