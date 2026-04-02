import Foundation

/// Unix domain socket server that listens on ~/.mission-control/mc.sock
@MainActor
class MCSocketServer {
    private let socketPath: String
    private var listenerFD: Int32 = -1
    private var clientConnections: [Int32: ClientConnection] = [:]
    private var listenerSource: DispatchSourceRead?

    var onStatusUpdate: ((IncomingMessage) -> Void)?
    var onPermissionRequest: ((IncomingMessage, Int32) -> Void)?
    var onPlanReview: ((IncomingMessage, Int32) -> Void)?

    struct ClientConnection {
        let fd: Int32
        var buffer: Data
        var source: DispatchSourceRead?
    }

    init() {
        let mcDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mission-control").path
        self.socketPath = "\(mcDir)/mc.sock"
    }

    func startListening() {
        // Ensure the directory exists
        let mcDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mission-control").path
        try? FileManager.default.createDirectory(atPath: mcDir, withIntermediateDirectories: true)

        // Remove stale socket file
        unlink(socketPath)

        // Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("MCSocketServer: failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        // Build sockaddr_un
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 104) { ptr in
                    _ = strncpy(ptr, src, 103)
                }
            }
        }

        // Bind
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("MCSocketServer: bind failed: \(String(cString: strerror(errno)))")
            close(fd)
            return
        }

        // Listen
        guard listen(fd, 16) == 0 else {
            print("MCSocketServer: listen failed: \(String(cString: strerror(errno)))")
            close(fd)
            return
        }

        listenerFD = fd

        // Set up dispatch source to accept connections
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.resume()
        listenerSource = source

        print("MCSocketServer: listening on \(socketPath)")
    }

    func stopListening() {
        listenerSource?.cancel()
        listenerSource = nil

        // Close all client connections
        for (_, var conn) in clientConnections {
            conn.source?.cancel()
            conn.source = nil
            close(conn.fd)
        }
        clientConnections.removeAll()

        if listenerFD >= 0 {
            close(listenerFD)
            listenerFD = -1
        }

        unlink(socketPath)
        print("MCSocketServer: stopped")
    }

    func sendResponse(to clientFD: Int32, message: OutgoingMessage) {
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(message) else {
            print("MCSocketServer: failed to encode response")
            return
        }
        data.append(0x0A) // newline
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = send(clientFD, baseAddress, data.count, 0)
        }
    }

    // MARK: - Private

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(listenerFD, sockPtr, &clientAddrLen)
            }
        }

        guard clientFD >= 0 else {
            print("MCSocketServer: accept failed: \(String(cString: strerror(errno)))")
            return
        }

        // Create a dispatch source for the client
        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: .main)
        let conn = ClientConnection(fd: clientFD, buffer: Data(), source: source)
        clientConnections[clientFD] = conn

        source.setEventHandler { [weak self] in
            self?.readFromClient(fd: clientFD)
        }
        source.setCancelHandler { [weak self] in
            self?.clientConnections.removeValue(forKey: clientFD)
            close(clientFD)
        }
        source.resume()

        print("MCSocketServer: client connected fd=\(clientFD)")
    }

    private func readFromClient(fd: Int32) {
        let bufferSize = 4096
        var rawBuffer = [UInt8](repeating: 0, count: bufferSize)
        let bytesRead = recv(fd, &rawBuffer, bufferSize, 0)

        if bytesRead <= 0 {
            // Client disconnected or error
            if let source = clientConnections[fd]?.source {
                source.cancel()
            }
            return
        }

        guard clientConnections[fd] != nil else { return }
        clientConnections[fd]!.buffer.append(contentsOf: rawBuffer[0..<bytesRead])

        // Scan for newline-delimited messages
        while let newlineIndex = clientConnections[fd]?.buffer.firstIndex(of: 0x0A) {
            guard let buffer = clientConnections[fd]?.buffer else { break }
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            clientConnections[fd]!.buffer = Data(buffer[(newlineIndex + 1)...])

            let decoder = JSONDecoder()
            if let msg = try? decoder.decode(IncomingMessage.self, from: lineData) {
                handleMessage(msg, from: fd)
            } else {
                let raw = String(data: lineData, encoding: .utf8) ?? "<non-utf8>"
                print("MCSocketServer: failed to decode message: \(raw)")
            }
        }
    }

    private func handleMessage(_ msg: IncomingMessage, from fd: Int32) {
        switch msg.type {
        case .statusUpdate:
            onStatusUpdate?(msg)
        case .permissionRequest:
            onPermissionRequest?(msg, fd)
        case .planReview:
            onPlanReview?(msg, fd)
        }
    }
}
