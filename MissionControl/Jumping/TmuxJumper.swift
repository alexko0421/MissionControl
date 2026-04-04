import Foundation

struct TmuxJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.tmux != nil && env.tmuxPane != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let tmuxTarget = agent.tmuxTarget else {
            throw JumpError.noTerminalInfo
        }
        let tmuxPath = findTmuxBinary()
        runTmux(tmuxPath, args: ["select-window", "-t", tmuxTarget])
        runTmux(tmuxPath, args: ["select-pane", "-t", tmuxTarget])
        try await GenericJumper.jump(env: env, agent: agent)
    }

    private static func findTmuxBinary() -> String {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "tmux"
    }

    @discardableResult
    private static func runTmux(_ path: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }
}
