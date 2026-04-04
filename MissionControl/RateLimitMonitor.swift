import Foundation
import Combine

@MainActor
class RateLimitMonitor: ObservableObject {
    @Published var rateLimits: RateLimits?

    struct RateLimits {
        var used5h: Int
        var limit5h: Int
        var used7d: Int
        var limit7d: Int

        var remaining5h: Int { limit5h - used5h }
        var remaining7d: Int { limit7d - used7d }
        var percent5h: Double { limit5h > 0 ? Double(remaining5h) / Double(limit5h) : 1.0 }
        var percent7d: Double { limit7d > 0 ? Double(remaining7d) / Double(limit7d) : 1.0 }
    }

    private let filePath = "/tmp/mc-rate-limits.json"
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?

    func startMonitoring() {
        readFile()

        if FileManager.default.fileExists(atPath: filePath) {
            watchFile()
        } else {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self = self else { timer.invalidate(); return }
                    if FileManager.default.fileExists(atPath: self.filePath) {
                        timer.invalidate()
                        self.pollTimer = nil
                        self.readFile()
                        self.watchFile()
                    }
                }
            }
        }
    }

    func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func watchFile() {
        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.readFile()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitor = source
    }

    private func readFile() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let used5h = json["requestsUsed5h"] as? Int ?? json["used_5h"] as? Int ?? 0
        let limit5h = json["requestsLimit5h"] as? Int ?? json["limit_5h"] as? Int ?? 0
        let used7d = json["requestsUsed7d"] as? Int ?? json["used_7d"] as? Int ?? 0
        let limit7d = json["requestsLimit7d"] as? Int ?? json["limit_7d"] as? Int ?? 0

        rateLimits = RateLimits(used5h: used5h, limit5h: limit5h, used7d: used7d, limit7d: limit7d)
    }
}
