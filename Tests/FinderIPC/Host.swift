import AppKit

/// Compiled only by scripts/test-finder-ipc.sh, using the production receiver.
@main
struct Host {
    @MainActor
    final class Delegate: NSObject, NSApplicationDelegate {
        private lazy var receiver = FinderPasteReceiver(authenticate: { token in
            let accepted = FinderPasteSenderAuthentication.accepts(token)
            Self.log(accepted ? "authenticated" : "rejected")
            return accepted
        }) { request in
            Self.log("delivered \(request.containerPath)")
        }

        static func log(_ line: String) {
            let path = Bundle.main.object(forInfoDictionaryKey: "IPCLogPath") as! String
            let handle = FileHandle(forWritingAtPath: path)!
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try! handle.close()
        }

        func applicationWillFinishLaunching(_ notification: Notification) {
            receiver.start()
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            receiver.finishLaunching()
            Self.log("launchRequest \(receiver.receivedLaunchRequest)")
            // Own only this disposable test process; never quit the user's app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { NSApp.terminate(nil) }
        }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
