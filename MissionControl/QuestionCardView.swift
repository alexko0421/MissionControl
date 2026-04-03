import SwiftUI

struct QuestionCardView: View {
    let agent: Agent
    let question: AgentQuestion
    @EnvironmentObject var store: AgentStore
    @State private var hoveredOption: Int? = nil
    @State private var freeText: String = ""
    @State private var isSendHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Question text
            Text(question.question)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(2)

            if question.isFreeInput {
                // Free text input
                HStack(spacing: 8) {
                    TextField("Type your response...", text: $freeText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit { sendFreeText() }

                    Button(action: { sendFreeText() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                freeText.isEmpty
                                    ? Color.white.opacity(0.2)
                                    : Color(red: 0.204, green: 0.827, blue: 0.600).opacity(isSendHovered ? 1.0 : 0.85)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(freeText.isEmpty)
                    .onHover { isSendHovered = $0 }
                }
            } else {
                // Numbered options
                VStack(spacing: 5) {
                    ForEach(question.options) { option in
                        Button(action: {
                            store.respondQuestion(agentId: agent.id, option: option)
                        }) {
                            HStack(spacing: 8) {
                                Text("\(option.id)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 20, height: 20)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(option.label)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Spacer()

                                if option.isHighlighted {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(hoveredOption == option.id
                                        ? Color.white.opacity(0.15)
                                        : (option.isHighlighted ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(option.isHighlighted ? Color.white.opacity(0.15) : Color.clear, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveredOption = $0 ? option.id : nil }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func sendFreeText() {
        guard !freeText.isEmpty else { return }
        store.respondFreeText(agentId: agent.id, text: freeText)
        freeText = ""
    }
}
