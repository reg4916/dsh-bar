import AppKit

// --dump-status: print one status snapshot and exit. Useful for debugging the
// bridge without opening the menu bar.
if CommandLine.arguments.contains("--dump-status") {
    let client = BarClient()
    let semaphore = DispatchSemaphore(value: 0)
    client.poll { result in
        switch result {
        case .success(let snapshot):
            print("state=\(snapshot.state.rawValue)")
            print("title=\(snapshot.title)")
            print("detail=\(snapshot.detail)")
            print("model=\(snapshot.model)")
            print("tokens=\(snapshot.tokens)")
            print("busy=\(snapshot.busy)")
            print("sessionId=\(snapshot.activeSessionId ?? "")")
            print("approvals=\(snapshot.approvalItems.map(\.toolName).joined(separator: ","))")
            print("questions=\(snapshot.questionCount)")
        case .failure(let error):
            print("error=\(error)")
            exit(1)
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 12)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
