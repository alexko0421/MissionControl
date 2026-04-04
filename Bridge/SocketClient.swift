import Foundation

struct SocketClient {
    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.mission-control/mc.sock"
    }()

    static func send(_ message: BridgeMessage, waitForResponse: Bool = false, timeout: TimeInterval = 86400) -> BridgeResponse? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

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
        guard connectResult == 0 else { close(fd); return nil }

        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(message) else { close(fd); return nil }
        data.append(0x0A)
        let sent = data.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return Darwin.send(fd, baseAddress, data.count, 0)
        }
        guard sent == data.count else { close(fd); return nil }

        if !waitForResponse {
            close(fd)
            return nil
        }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buffer = Data()
        var rawBuffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = recv(fd, &rawBuffer, rawBuffer.count, 0)
            if bytesRead <= 0 { break }
            buffer.append(contentsOf: rawBuffer[0..<bytesRead])
            if buffer.contains(0x0A) { break }
        }
        close(fd)

        guard let newlineIdx = buffer.firstIndex(of: 0x0A) else {
            return BridgeResponse(decision: "approve")
        }
        let lineData = buffer[buffer.startIndex..<newlineIdx]
        return try? JSONDecoder().decode(BridgeResponse.self, from: Data(lineData))
    }
}
