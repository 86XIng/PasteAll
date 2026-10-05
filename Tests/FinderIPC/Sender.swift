import AppKit

@main
struct Sender {
    static func main() {
        let host = URL(fileURLWithPath: CommandLine.arguments[1])
        let label = CommandLine.arguments[2]
        func send(_ suffix: String) {
            let request = FinderPasteRequest(containerPath: "/\(label)-\(suffix)", selectedPaths: [], choosesFormat: false)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.open([request.url!], withApplicationAt: host, configuration: configuration) { _, error in
                if let error { print(error); exit(1) }
            }
        }
        send("cold")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { send("warm") }
        // Sender must remain alive while Security resolves its audit token.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
        RunLoop.main.run()
    }
}
