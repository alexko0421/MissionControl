import AppKit

struct GhosttyJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        let prog = env.termProgram?.lowercased() ?? ""
        return prog == "ghostty" || prog == "xterm-ghostty"
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        let script = """
        tell application "Ghostty"
            activate
        end tell
        tell application "System Events"
            tell process "Ghostty"
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
