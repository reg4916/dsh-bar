import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let client = BarClient()

    private var frameTimer: Timer?
    private var pollTimer: Timer?
    private var frame = 0
    private var demo = false
    private var demoIndex = 0
    private var demoSnapshot = BarSnapshot.demo[0]
    private var snapshot = BarSnapshot()
    private var connected = false
    private var inflight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        demo = ProcessInfo.processInfo.environment["DSH_BAR_DEMO"] == "1"
        configureStatusItem()
        configurePopover()
        startFrameTimer()
        if demo {
            startDemoTimer()
        } else {
            startPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        frameTimer?.invalidate()
        pollTimer?.invalidate()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = WhaleIcon.image(frame: 0, state: .idle)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "DSH Bar"
        updateBadge()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = StatusViewController(
            snapshot: snapshot,
            onApprove: { [weak self] id in self?.decide(id: id, outcome: "allowed-once") },
            onDeny: { [weak self] id in self?.decide(id: id, outcome: "rejected") },
            onOpen: { [weak self] in self?.openActiveSession() },
            onStop: { [weak self] in self?.stopActive() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    private func startFrameTimer() {
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.onFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func startPolling() {
        poll()
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func startDemoTimer() {
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            demoIndex = (demoIndex + 1) % BarSnapshot.demo.count
            demoSnapshot = BarSnapshot.demo[demoIndex]
            apply(demoSnapshot, connected: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard !inflight, !demo else { return }
        inflight = true
        client.poll { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inflight = false
                switch result {
                case .success(let next):
                    self.apply(next, connected: true)
                case .failure(let error):
                    var offline = BarSnapshot()
                    offline.title = "DSH is not running"
                    offline.detail = String(describing: error)
                    self.apply(offline, connected: false)
                }
            }
        }
    }

    private func apply(_ next: BarSnapshot, connected: Bool) {
        let changed = next.state != snapshot.state
            || next.title != snapshot.title
            || next.detail != snapshot.detail
            || next.approvalItems.map(\.id) != snapshot.approvalItems.map(\.id)
            || next.questionCount != snapshot.questionCount
            || next.busy != snapshot.busy
            || next.activeSessionId != snapshot.activeSessionId
        self.connected = connected
        snapshot = next
        if changed {
            (popover.contentViewController as? StatusViewController)?.update(snapshot)
        }
        statusItem.button?.appearsDisabled = !connected
        redraw(force: changed)
        updateBadge()
    }

    private func onFrame() {
        frame += 1
        redraw(force: false)
    }

    private func redraw(force: Bool) {
        guard let button = statusItem.button else { return }
        if snapshot.state.animates || force || frame % 12 == 0 {
            button.image = WhaleIcon.image(frame: frame, state: snapshot.state)
        }
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        if snapshot.approvals > 0 {
            let title = NSMutableAttributedString()
            if snapshot.questionCount > 0 {
                title.append(NSAttributedString(string: String(snapshot.approvals + snapshot.questionCount)))
            }
            let dot = NSMutableAttributedString(string: "\u{2009}\u{25CF}")
            dot.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: dot.length))
            dot.addAttribute(.font, value: NSFont.systemFont(ofSize: 9, weight: .bold), range: NSRange(location: 0, length: dot.length))
            title.append(dot)
            button.attributedTitle = title
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func decide(id: String, outcome: String) {
        client.post(path: "/dsh-bar/approve", body: ["id": id, "outcome": outcome]) { [weak self] _ in
            DispatchQueue.main.async { self?.poll() }
        }
    }

    private func stopActive() {
        guard let sessionId = snapshot.activeSessionId, connected else { return }
        client.post(path: "/dsh-bar/stop", body: ["sessionId": sessionId]) { [weak self] _ in
            DispatchQueue.main.async { self?.poll() }
        }
    }

    private func openActiveSession() {
        guard connected, let sessionId = snapshot.activeSessionId else {
            activateDSH()
            return
        }
        client.post(path: "/dsh-bar/focus", body: ["sessionId": sessionId]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.activateDSH()
                self?.poll()
            }
        }
    }

    private func activateDSH() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.deepseek.dsh").first {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let raw = ProcessInfo.processInfo.environment["DSH_BAR_URL"] ?? "http://127.0.0.1:49399"
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Launch at login (LaunchAgent, works without a paid Developer ID)

    private var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.reg4916.dsh-bar.plist"
    }

    private var launchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAtLoginEnabled {
            try? FileManager.default.removeItem(atPath: launchAgentPath)
        } else {
            let directory = NSHomeDirectory() + "/Library/LaunchAgents"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": "com.reg4916.dsh-bar",
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Background",
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: URL(fileURLWithPath: launchAgentPath))
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open DSH", action: #selector(menuOpen), keyEquivalent: "o").target = self
        if snapshot.busy {
            menu.addItem(withTitle: "Stop Current Turn", action: #selector(menuStop), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DSH Bar", action: #selector(menuQuit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpen() { openActiveSession() }
    @objc private func menuStop() { stopActive() }
    @objc private func menuQuit() { NSApplication.shared.terminate(nil) }
}

/// Popover content: session snapshot, approvals with Approve/Deny, Stop,
/// Open DSH and Quit. Rebuilt only when something actually changes.
final class StatusViewController: NSViewController {
    private var snapshot: BarSnapshot
    private var signature = ""
    private let stack = NSStackView()
    private let onApprove: (String) -> Void
    private let onDeny: (String) -> Void
    private let onOpen: () -> Void
    private let onStop: () -> Void
    private let onQuit: () -> Void

    init(snapshot: BarSnapshot,
         onApprove: @escaping (String) -> Void,
         onDeny: @escaping (String) -> Void,
         onOpen: @escaping () -> Void,
         onStop: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onOpen = onOpen
        self.onStop = onStop
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 320),
        ])
        view = container
        render()
    }

    func update(_ snapshot: BarSnapshot) {
        self.snapshot = snapshot
        guard isViewLoaded else { return }
        render()
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        stack.addArrangedSubview(label(snapshot.title, size: 13, weight: .semibold))
        if !snapshot.detail.isEmpty {
            stack.addArrangedSubview(label(snapshot.detail, size: 11, color: .secondaryLabelColor))
        }
        let tokens = NumberFormatter.localizedString(from: NSNumber(value: snapshot.tokens), number: .decimal)
        stack.addArrangedSubview(label("\(snapshot.state.label) · \(snapshot.model) · \(tokens) tok", size: 10, color: .tertiaryLabelColor))

        if let approval = snapshot.approvalItems.first {
            let reason = approval.reason.map { " — " + $0 } ?? ""
            stack.addArrangedSubview(label("Approval: " + approval.toolName + reason, size: 11, color: .systemOrange))
            let row = NSStackView(views: [button("Approve", action: #selector(approveTapped)), button("Deny", action: #selector(denyTapped))])
            row.orientation = .horizontal
            row.spacing = 8
            stack.addArrangedSubview(row)
        }

        if snapshot.questionCount > 0 {
            stack.addArrangedSubview(label("Question waiting — open DSH to answer", size: 11, color: .systemOrange))
        }

        let actions = NSStackView(views: [button("Open DSH", action: #selector(openTapped))])
        actions.orientation = .horizontal
        actions.spacing = 8
        if snapshot.busy {
            actions.addArrangedSubview(button("Stop", action: #selector(stopTapped)))
        }
        actions.addArrangedSubview(button("Quit", action: #selector(quitTapped)))
        stack.addArrangedSubview(actions)
    }

    @objc private func approveTapped() {
        if let approval = snapshot.approvalItems.first { onApprove(approval.id) }
    }

    @objc private func denyTapped() {
        if let approval = snapshot.approvalItems.first { onDeny(approval.id) }
    }

    @objc private func openTapped() { onOpen() }
    @objc private func stopTapped() { onStop() }
    @objc private func quitTapped() { onQuit() }
}
