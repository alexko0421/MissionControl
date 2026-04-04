import AppKit

struct GenericJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool { true }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        let appName = agent.displayApp
        let script = """
        tell application "\(appName)"
            activate
        end tell
        tell application "System Events"
            tell process "\(appName)"
                set frontmost to true
                try
                    perform action "AXRaise" of window 1
                end try
            end tell
        end tell
        """
        try await runAppleScript(script)
    }

    static func runAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                var errorDict: NSDictionary?
                let appleScript = NSAppleScript(source: source)
                appleScript?.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: JumpError.appleScriptFailed(msg))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
