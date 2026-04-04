import Foundation

struct JumpEngine {
    static let jumpers: [TerminalJumper.Type] = [
        ITermJumper.self,
        GhosttyJumper.self,
        TerminalAppJumper.self,
        VSCodeJumper.self,
        KittyJumper.self,
        WarpJumper.self,
        CmuxJumper.self,
        TmuxJumper.self,
        GenericJumper.self,
    ]

    static func jump(to agent: Agent) async {
        let env = agent.terminalEnv ?? TerminalEnv()
        for jumper in jumpers {
            if jumper.canHandle(env: env) {
                do {
                    try await jumper.jump(env: env, agent: agent)
                } catch {
                    print("JumpEngine: \(type(of: jumper)) failed: \(error), trying next...")
                    continue
                }
                return
            }
        }
    }
}
