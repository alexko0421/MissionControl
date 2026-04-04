import Foundation

struct CmuxJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.cmuxSocketPath != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let socketPath = env.cmuxSocketPath,
              let surfaceId = env.cmuxSurfaceId else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 104) { ptr in
                    _ = strncpy(ptr, src, 103)
                }
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }
        let rpc = "{\"method\":\"focus\",\"params\":{\"surface\":\"\(surfaceId)\"}}\n"
        _ = rpc.withCString { ptr in
            send(fd, ptr, strlen(ptr), 0)
        }
    }
}
