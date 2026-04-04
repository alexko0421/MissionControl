import AppKit

struct WarpJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.termProgram?.lowercased() == "warpterminal"
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        let script = """
        tell application "Warp"
            activate
        end tell
        tell application "System Events"
            tell process "Warp"
                set frontmost to true
                try
                    perform action "AXRaise" of window 1
                end try
            end tell
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
