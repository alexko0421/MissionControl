import Foundation

@MainActor
class HookGuard {
    private var fileMonitors: [DispatchSourceFileSystemObject] = []
    private var expectedHooks: [String: [[String: Any]]] = [:]

    private let claudeSettingsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
    }()

    func startGuarding() {
        recordBaseline()
        watchFile(at: claudeSettingsPath)
    }

    func stopGuarding() {
        for monitor in fileMonitors {
            monitor.cancel()
        }
        fileMonitors.removeAll()
    }

    private func recordBaseline() {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: [[String: Any]]] else {
            return
        }
        for (event, entries) in hooks {
            let ours = entries.filter { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { hook in
                    (hook["command"] as? String)?.contains("mc-bridge") == true
                }
            }
            if !ours.isEmpty {
                expectedHooks[event] = ours
            }
        }
    }

    private func watchFile(at path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkAndRecover()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitors.append(source)
    }

    private func checkAndRecover() {
        guard !expectedHooks.isEmpty else { return }
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var hooks = json["hooks"] as? [String: [[String: Any]]] ?? [:]
        var needsWrite = false

        for (event, ourEntries) in expectedHooks {
            let existing = hooks[event] ?? []
            let hasOurs = existing.contains { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { hook in
                    (hook["command"] as? String)?.contains("mc-bridge") == true
                }
            }
            if !hasOurs {
                hooks[event] = existing + ourEntries
                needsWrite = true
                print("HookGuard: recovered \(event) hook")
            }
        }

        if needsWrite {
            json["hooks"] = hooks
            if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? newData.write(to: URL(fileURLWithPath: claudeSettingsPath))
            }
        }
    }
}
