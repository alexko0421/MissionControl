import AppKit

struct VSCodeJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        let bundle = env.cfBundleIdentifier?.lowercased() ?? ""
        return bundle.contains("vscode") || bundle.contains("cursor") || bundle.contains("windsurf")
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        let bundle = env.cfBundleIdentifier?.lowercased() ?? ""
        let scheme: String
        if bundle.contains("cursor") { scheme = "cursor" }
        else if bundle.contains("windsurf") { scheme = "windsurf" }
        else { scheme = "vscode" }

        let tty = agent.tty ?? ""
        let url = "\(scheme)://missioncontrol.terminal-focus/jump?tty=\(tty)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try await GenericJumper.jump(env: env, agent: agent)
        }
    }
}
