import Foundation

func parseArgs() -> (source: String, event: String, cwd: String?) {
    var source = "claude"
    var event = ""
    var cwd: String? = nil
    let args = CommandLine.arguments

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--source":
            i += 1; if i < args.count { source = args[i] }
        case "--event":
            i += 1; if i < args.count { event = args[i] }
        case "--cwd":
            i += 1; if i < args.count { cwd = args[i] }
        default:
            break
        }
        i += 1
    }
    return (source, event, cwd)
}

func readStdin() -> [String: Any] {
    var input = ""
    while let line = readLine(strippingNewline: false) {
        input += line
    }
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return [:]
    }
    guard let data = input.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

let (source, event, cwdArg) = parseArgs()

guard !event.isEmpty else {
    fputs("Usage: mc-bridge --source <source> --event <event> [--cwd <path>]\n", stderr)
    exit(1)
}

var hookInput = readStdin()
if let cwd = cwdArg {
    hookInput["cwd"] = cwd
}

let router = HookRouter(source: source, event: event, hookInput: hookInput)
router.route()
