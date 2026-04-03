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
            // Header badge by type
            promptHeader

            // Question text
            Text(question.question)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(2)

            // Diff preview (if applicable)
            if let diff = question.diffContext {
                ScrollView {
                    Text(diff)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if question.isFreeInput {
                freeInputView
            } else {
                optionsView
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
    }

    // MARK: - Header

    @ViewBuilder
    private var promptHeader: some View {
        switch question.promptType {
        case .numbered:
            EmptyView()  // no extra header needed
        case .yesNo:
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Confirm")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
        case .arrowSelect:
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Text("Select")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.365, green: 0.631, blue: 0.847))
        case .diff:
            HStack(spacing: 5) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Review Changes")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.659, green: 0.549, blue: 0.969))
        case .freeInput:
            HStack(spacing: 5) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Input Required")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.204, green: 0.827, blue: 0.600))
        }
    }

    // MARK: - Border color by type

    private var borderColor: Color {
        switch question.promptType {
        case .numbered: return .white
        case .yesNo: return Color(red: 0.937, green: 0.624, blue: 0.153)
        case .arrowSelect: return Color(red: 0.365, green: 0.631, blue: 0.847)
        case .diff: return Color(red: 0.659, green: 0.549, blue: 0.969)
        case .freeInput: return Color(red: 0.204, green: 0.827, blue: 0.600)
        }
    }

    // MARK: - Options View

    private var optionsView: some View {
        VStack(spacing: 5) {
            ForEach(question.options) { option in
                Button(action: {
                    store.respondQuestion(agentId: agent.id, option: option)
                }) {
                    HStack(spacing: 8) {
                        if question.promptType == .yesNo || question.promptType == .diff {
                            // Color-coded for y/n style
                            let isYes = option.sendKey == "y" || option.sendKey == "Enter"
                            Image(systemName: isYes ? "checkmark" : "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isYes ? .black : .white)
                                .frame(width: 20, height: 20)
                                .background(isYes
                                    ? Color(red: 0.204, green: 0.827, blue: 0.600)
                                    : Color(red: 0.937, green: 0.267, blue: 0.267))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Text("\(option.id)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

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

    // MARK: - Free Input View

    private var freeInputView: some View {
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
    }

    private func sendFreeText() {
        guard !freeText.isEmpty else { return }
        store.respondFreeText(agentId: agent.id, text: freeText)
        freeText = ""
    }
}
