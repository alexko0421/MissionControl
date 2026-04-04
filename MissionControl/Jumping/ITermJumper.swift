import AppKit

struct ITermJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.itermSessionId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let sessionId = env.itermSessionId else {
            throw JumpError.noTerminalInfo
        }
        let script = """
        tell application "iTerm2"
            activate
            repeat with aWin in windows
                tell aWin
                    repeat with aTab in tabs
                        tell aTab
                            repeat with aSession in sessions
                                tell aSession
                                    if (variable named "session.uniqueID") contains "\(sessionId)" then
                                        select
                                        set selected tab of aWin to aTab
                                        tell application "System Events"
                                            tell process "iTerm2"
                                                perform action "AXRaise" of window 1
                                            end tell
                                        end tell
                                        return
                                    end if
                                end tell
                            end repeat
                        end tell
                    end repeat
                end tell
            end repeat
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
