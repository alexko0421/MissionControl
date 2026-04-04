import Foundation

struct KittyJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.kittyWindowId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let windowId = env.kittyWindowId else {
            throw JumpError.noTerminalInfo
        }
        let kittyPaths = ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty", "/Applications/kitty.app/Contents/MacOS/kitty"]
        guard let kittyPath = kittyPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kittyPath)
        process.arguments = ["@", "focus-window", "--match", "id:\(windowId)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
