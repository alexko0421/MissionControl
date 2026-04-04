import AppKit

struct TerminalAppJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.termSessionId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let sessionId = env.termSessionId else {
            throw JumpError.noTerminalInfo
        }
        let script = """
        tell application "Terminal"
            activate
            repeat with aWin in windows
                repeat with aTab in tabs of aWin
                    if tty of aTab contains "\(sessionId)" then
                        set selected tab of aWin to aTab
                        set index of aWin to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
