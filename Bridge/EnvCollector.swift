import Foundation

struct EnvCollector {
    static let envKeys = [
        "ITERM_SESSION_ID",
        "TERM_SESSION_ID",
        "TERM_PROGRAM",
        "TMUX",
        "TMUX_PANE",
        "KITTY_WINDOW_ID",
        "__CFBundleIdentifier",
        "CMUX_WORKSPACE_ID",
        "CMUX_SURFACE_ID",
        "CMUX_SOCKET_PATH",
    ]

    static func collect() -> [String: String] {
        var result: [String: String] = [:]
        for key in envKeys {
            if let value = ProcessInfo.processInfo.environment[key] {
                result[key] = value
            }
        }
        return result
    }

    static func detectApp() -> String {
        let bundleId = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""
        let mapping: [String: String] = [
            "com.apple.Terminal": "Terminal",
            "com.google.antigravity": "Antigravity",
            "com.mitchellh.ghostty": "Ghostty",
            "com.microsoft.VSCode": "VS Code",
            "com.todesktop.runtime.cursor": "Cursor",
            "dev.warp.Warp-Stable": "Warp",
            "net.kovidgoyal.kitty": "Kitty",
        ]
        if let name = mapping[bundleId] { return name }
        if !bundleId.isEmpty {
            return bundleId.split(separator: ".").last.map(String.init)?.capitalized ?? "Terminal"
        }
        return "Terminal"
    }

    static func detectTmux() -> (session: String?, window: Int, pane: Int) {
        guard ProcessInfo.processInfo.environment["TMUX"] != nil else {
            return (nil, 0, 0)
        }
        func tmuxQuery(_ format: String) -> String? {
            let process = Process()
            let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            guard let tmuxPath = tmuxPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                return nil
            }
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["display-message", "-p", format]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        let session = tmuxQuery("#{session_name}")
        let window = Int(tmuxQuery("#{window_index}") ?? "0") ?? 0
        let pane = Int(tmuxQuery("#{pane_index}") ?? "0") ?? 0
        return (session, window, pane)
    }

    static func tty() -> String? {
        if isatty(STDIN_FILENO) != 0 {
            return String(cString: ttyname(STDIN_FILENO))
        }
        return ProcessInfo.processInfo.environment["TTY"]
    }

    static func projectName(cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd, "branch", "--show-current"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            var branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !branch.isEmpty {
                if let slashIdx = branch.firstIndex(of: "/") {
                    branch = String(branch[branch.index(after: slashIdx)...])
                }
                return branch.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            }
        } catch {}
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}
