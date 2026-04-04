import Foundation

protocol TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool
    static func jump(env: TerminalEnv, agent: Agent) async throws
}

enum JumpError: Error {
    case noTerminalInfo
    case appleScriptFailed(String)
    case processNotFound
}
