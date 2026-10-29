import AppKit
import UserNotifications

// --notification-status: print the current authorization without prompting.
if CommandLine.arguments.contains("--notification-status") {
    let semaphore = DispatchSemaphore(value: 0)
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        print("authorization=\(settings.authorizationStatus.rawValue)")
        print("alert=\(settings.alertSetting.rawValue)")
        print("sound=\(settings.soundSetting.rawValue)")
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
    exit(0)
}

// --update-check: print the newer release tag, if any, and exit.
if CommandLine.arguments.contains("--update-check") {
    let semaphore = DispatchSemaphore(value: 0)
    UpdateChecker.check { tag in
        print("latest=" + (tag ?? "none"))
        print("current=" + UpdateChecker.currentVersion)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 15)
    exit(0)
}

// --alert-test: show the in-app fallback card for a few seconds and exit.
if CommandLine.arguments.contains("--alert-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let presenter = AlertPresenter()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        presenter.approval(id: "demo", tool: "bash", reason: "write src/parser.ts")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
    app.run()
}

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
