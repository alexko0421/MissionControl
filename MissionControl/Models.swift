import Foundation
import SwiftUI

// MARK: - Status

enum AgentStatus: String, Codable, CaseIterable {
    case running, blocked, done, idle

    var label: String { labelFor(lang: Agent.displayLanguage) }

    func labelFor(lang: String) -> String {
        let isEn = (lang == "En")
        switch self {
        case .running: return isEn ? "Running" : "進行中"
        case .blocked: return isEn ? "Action" : "需要你"
        case .done:    return isEn ? "Done" : "已完成"
        case .idle:    return isEn ? "Idle" : "閒置"
        }
    }

    var color: Color {
        switch self {
        case .running: return Color(red: 0.365, green: 0.792, blue: 0.647)
        case .blocked: return Color(red: 0.937, green: 0.624, blue: 0.153)
        case .done:    return Color(red: 0.216, green: 0.541, blue: 0.867)
        case .idle:    return Color.white.opacity(0.3)
        }
    }

    var hasPulse: Bool { self == .running }
}

// MARK: - Terminal Line

struct TerminalLine: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var type: LineType

    enum LineType: String, Codable {
        case normal, success, warning, error

        var color: Color {
            switch self {
            case .normal:  return .primary.opacity(0.5)
            case .success: return Color(red: 0.365, green: 0.792, blue: 0.647)
            case .warning: return Color(red: 0.937, green: 0.624, blue: 0.153)
            case .error:   return Color(red: 0.886, green: 0.294, blue: 0.290)
            }
        }
    }

    init(text: String, type: LineType = .normal) {
        self.id = UUID()
        self.text = text
        self.type = type
    }

    // Custom Codable to handle UUID
    enum CodingKeys: String, CodingKey { case id, text, type }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        type = (try? c.decode(LineType.self, forKey: .type)) ?? .normal
    }
}

// MARK: - Agent

struct Agent: Identifiable, Codable {
    var id: String
    var name: String
    var status: AgentStatus
    var task: String
    var summary: String
    var terminalLines: [TerminalLine]
    var nextAction: String
    var updatedAt: Date
    var worktree: String?
    var tmuxSession: String?
    var tmuxWindow: Int?
    var tmuxPane: Int?

    /// Shared language setting — set by the app on launch / change
    static var displayLanguage: String = "Auto"

    var timeAgo: String {
        let s = Date().timeIntervalSince(updatedAt)
        let isEn = (Agent.displayLanguage == "En")
        if s < 60   { return isEn ? "Just now" : "剛剛" }
        if s < 3600 { return isEn ? "\(Int(s / 60))m ago" : "\(Int(s / 60))分鐘前" }
        return isEn ? "\(Int(s / 3600))h ago" : "\(Int(s / 3600))小時前"
    }

    var tmuxTarget: String? {
        guard let session = tmuxSession else { return nil }
        return "\(session):\(tmuxWindow ?? 0).\(tmuxPane ?? 0)"
    }
}

// MARK: - Sample Data

extension Agent {
    static var samples: [Agent] {[
        Agent(
            id: "asami-voice",
            name: "ASAMI 語音流程",
            status: .running,
            task: "重構 Gemini Live session handler...",
            summary: "重構了 session 生命週期，init、active、teardown 已分離成獨立狀態。Gemini Live 連線穩定性有所提升。",
            terminalLines: [
                TerminalLine(text: "$ git checkout worktree/asami-voice"),
                TerminalLine(text: "重構 session_manager.ts..."),
                TerminalLine(text: "✓ SessionInit 已抽離成獨立模組", type: .success),
                TerminalLine(text: "✓ 網絡中斷時 teardown 正確觸發", type: .success),
                TerminalLine(text: "執行整合測試中..."),
            ],
            nextAction: "測試全部通過，可以合併入主語音分支。",
            updatedAt: Date().addingTimeInterval(-120),
            worktree: "asami-voice",
            tmuxSession: "conductor",
            tmuxWindow: 0,
            tmuxPane: 0
        ),
        Agent(
            id: "grammar-studio",
            name: "GrammarStudio 介面",
            status: .blocked,
            task: "等待：動畫緩動方式選擇？",
            summary: "新學習階段的卡片切換動畫已完成。兩個緩動選項都準備好了，需要你決定方向。",
            terminalLines: [
                TerminalLine(text: "$ 建構 GrammarStudio 切換層"),
                TerminalLine(text: "✓ 卡片翻轉動畫完成", type: .success),
                TerminalLine(text: "✓ 進度指示器已與狀態連結", type: .success),
                TerminalLine(text: "⚠ 等待：緩動曲線決定", type: .warning),
                TerminalLine(text: "  選項：ease-out-cubic | spring(1, 0.6)"),
            ],
            nextAction: "確認緩動方式後，我會完成並進行視覺 QA。",
            updatedAt: Date().addingTimeInterval(-300),
            worktree: "grammar-studio"
        ),
        Agent(
            id: "vocab-audit",
            name: "詞彙資料集審核",
            status: .done,
            task: "已完成 A1-B2 詞性標準化",
            summary: "4,230 個 A1-B2 詞條全部審核完畢。修正了 47 個詞性錯誤。12 個翻譯準確度問題已標記，需人工覆核。",
            terminalLines: [
                TerminalLine(text: "$ 審核 vocab_dataset.json"),
                TerminalLine(text: "✓ 詞性標準化完成", type: .success),
                TerminalLine(text: "✓ 47 個錯誤已修正", type: .success),
                TerminalLine(text: "⚠ 12 個詞條已標記待人工覆核", type: .warning),
                TerminalLine(text: "✓ 任務完成", type: .success),
            ],
            nextAction: "請查閱 /audit/flagged.json 中的 12 個標記詞條。",
            updatedAt: Date().addingTimeInterval(-720)
        ),
        Agent(
            id: "l10n-bug",
            name: "本地化 Bug 修復",
            status: .blocked,
            task: "ASAMI 輸出語言錯誤，需要你決定方向",
            summary: "找到根本原因：語言偵測在用戶資料載入前就觸發，ASAMI 因此預設輸出英文。有兩個修復方案。",
            terminalLines: [
                TerminalLine(text: "$ 調試 asami_locale.ts"),
                TerminalLine(text: "追蹤語言偵測鏈..."),
                TerminalLine(text: "✗ 語言偵測在資料載入前觸發", type: .error),
                TerminalLine(text: "  方案 A：延遲語言初始化至資料載入後"),
                TerminalLine(text: "  方案 B：將語言作為 session 初始化參數傳入"),
                TerminalLine(text: "⚠ 等待你的決定", type: .warning),
            ],
            nextAction: "選擇方案 A 或 B，或提出其他思路。",
            updatedAt: Date().addingTimeInterval(-480),
            worktree: "l10n-fix"
        ),
    ]}
}
