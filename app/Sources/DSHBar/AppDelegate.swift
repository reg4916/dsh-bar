import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let client = BarClient()
    private let notifier = BarNotifier()
    private let hotKey = GlobalHotKey()
    private let stream = BarStream()
    private var settingsWindow: SettingsWindowController?

    private var frameTimer: Timer?
    private var pollTimer: Timer?
    private var frame = 0
    private var demo = false
    private var demoIndex = 0
    private var demoSnapshot = BarSnapshot.demo[0]
    private var snapshot = BarSnapshot()
    private var connected = false
    private var inflight = false
    private var autoAnswered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        demo = ProcessInfo.processInfo.environment["DSH_BAR_DEMO"] == "1"
        notifier.onDenyApproval = { [weak self] id in self?.decide(id: id, outcome: "rejected") }
        notifier.onOpen = { [weak self] _ in self?.openActiveSession() }
        notifier.start()
        hotKey.onPress = { [weak self] in self?.togglePopover() }
        if Settings.shared.hotKeyEnabled { hotKey.register() }
        NotificationCenter.default.addObserver(forName: .dshBarSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if Settings.shared.hotKeyEnabled {
                self.hotKey.register()
            } else {
                self.hotKey.unregister()
            }
            self.redraw(force: true)
            (self.popover.contentViewController as? StatusViewController)?.update(self.snapshot)
        }
        configureStatusItem()
        configurePopover()
        startFrameTimer()
        if ProcessInfo.processInfo.environment["DSH_BAR_DEMO_QUESTION"] == "1" {
            showQuestionPreview()
            return
        }
        if ProcessInfo.processInfo.environment["DSH_BAR_SHOW_SETTINGS"] == "1" {
            startPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.openSettings() }
            return
        }
        if demo {
            startDemoTimer()
        } else {
            startPolling()
            startStreaming()
        }
    }

    private func startStreaming() {
        stream.onStatus = { [weak self] status in
            guard let self else { return }
            self.apply(BarClient.snapshot(from: status), connected: true)
        }
        stream.onDisconnect = { [weak self] _ in
            guard let self else { return }
            self.stream.stop()
            self.poll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.demo else { return }
                self.stream.start()
            }
        }
        stream.start()
    }

    /// Static snapshot with a question, used to screenshot the composer.
    private func showQuestionPreview() {
        let long = ProcessInfo.processInfo.environment["DSH_BAR_DEMO_LONG"] == "1"
        var options = [
            BarOption(label: "Recursive descent", description: "simpler"),
            BarOption(label: "PEG", description: "more flexible"),
        ]
        if long {
            options += (3...8).map { BarOption(label: "Strategy \($0)", description: nil) }
        }
        var sessions = [
            BarSession(id: "s1", title: "Refactor the parser", state: .thinking, busy: true, waiting: false),
            BarSession(id: "s2", title: "Plugin docs", state: .idle, busy: false, waiting: false),
        ]
        if long {
            sessions = (0..<8).map { index in
                BarSession(id: "s\(index)", title: "Session \(index) — longer title", state: .idle, busy: false, waiting: false)
            }
        }
        var preview = BarSnapshot()
        preview.state = .thinking
        preview.title = "Refactor the parser"
        preview.detail = "Tool: bash"
        preview.model = "deepseek-flash"
        preview.tokens = 18_420
        preview.busy = true
        preview.questionGroups = [BarQuestionGroup(
            id: "demo-question",
            sessionId: "s1",
            title: "Refactor the parser",
            questions: [BarQuestion(
                id: "q1",
                question: "Which parser should we keep?",
                detail: "Both strategies parse the same grammar.",
                header: "Parser choice",
                options: options,
                multiSelect: false
            )]
        )]
        preview.questionCount = 1
        preview.sessions = sessions
        apply(preview, connected: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
            onQuit: { NSApplication.shared.terminate(nil) },
            onAnswer: { [weak self] heldId, answers in self?.sendAnswer(heldId: heldId, answers: answers) },
            onFocus: { [weak self] sessionId in self?.focus(sessionId: sessionId) }
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
                    offline.title = L("status.offline")
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
        notifier.sync(next, enabled: Settings.shared.notificationsEnabled)
        if ProcessInfo.processInfo.environment["DSH_BAR_AUTOANSWER"] == "1" {
            if next.questionGroups.isEmpty {
                autoAnswered = false
            } else if !autoAnswered {
                autoAnswered = true
                if let button = statusItem.button {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    (self?.popover.contentViewController as? StatusViewController)?.autoAnswerFirstOption()
                }
            }
        }
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
        if Settings.shared.dotOnly {
            if force || frame % 12 == 0 {
                button.image = WhaleIcon.dot(state: snapshot.state)
            }
            return
        }
        let animated = snapshot.state.animates && Settings.shared.animates
        if animated || force || frame % 12 == 0 {
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

    private func sendAnswer(heldId: String, answers: [[String: Any]]) {
        client.answer(heldId: heldId, answers: answers) { [weak self] _ in
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
        focus(sessionId: snapshot.activeSessionId)
    }

    private func focus(sessionId: String?) {
        guard connected, let sessionId else {
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

    private var launchAtLoginEnabled: Bool {
        LaunchAgent.enabled
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAgent.setEnabled(!LaunchAgent.enabled)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check { [weak self] tag in
            let alert = NSAlert()
            if let tag {
                alert.messageText = Lf("update.available.title", tag)
                alert.informativeText = L("update.available.body")
                alert.addButton(withTitle: L("action.open"))
                alert.addButton(withTitle: L("action.later"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(UpdateChecker.releasesURL)
                }
            } else {
                alert.messageText = L("update.none.title")
                alert.informativeText = Lf("update.none.body", UpdateChecker.currentVersion)
                alert.addButton(withTitle: L("action.ok"))
                alert.runModal()
            }
            _ = self
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
            return
        }
        togglePopover()
    }

    /// Shared by the status item click and the global hotkey.
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("menu.open"), action: #selector(menuOpen), keyEquivalent: "o").target = self
        if snapshot.busy {
            menu.addItem(withTitle: L("menu.stop"), action: #selector(menuStop), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("menu.checkUpdates"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = NSMenuItem(title: L("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.quit"), action: #selector(menuQuit), keyEquivalent: "q").target = self
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
    private let onAnswer: (String, [[String: Any]]) -> Void
    private let onFocus: (String) -> Void
    private var approvalIndex = 0
    private var optionButtons: [[NSButton]] = []
    private var customFields: [NSTextField] = []
    private var sendButton: NSButton?
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private var documentHeight: NSLayoutConstraint?

    init(snapshot: BarSnapshot,
         onApprove: @escaping (String) -> Void,
         onDeny: @escaping (String) -> Void,
         onOpen: @escaping () -> Void,
         onStop: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onAnswer: @escaping (String, [[String: Any]]) -> Void,
         onFocus: @escaping (String) -> Void) {
        self.snapshot = snapshot
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onOpen = onOpen
        self.onStop = onStop
        self.onQuit = onQuit
        self.onAnswer = onAnswer
        self.onFocus = onFocus
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        // NSPopover uses a vibrant material that lets the window behind bleed
        // through; paint the content solid so text stays readable.
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 320),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
        view = container
        render()
        updatePreferredSize()
    }

    func update(_ snapshot: BarSnapshot) {
        self.snapshot = snapshot
        guard isViewLoaded else { return }
        render()
        updatePreferredSize()
    }

    /// NSPopover otherwise keeps its initial frame and clips the last row.
    /// Long questions/session lists scroll inside a capped height instead of
    /// growing past the screen.
    private func updatePreferredSize() {
        view.layoutSubtreeIfNeeded()
        let content = max(1, stack.fittingSize.height)
        documentHeight?.isActive = false
        documentHeight = documentView.heightAnchor.constraint(equalToConstant: content)
        documentHeight?.isActive = true
        let height = min(max(140, content), 640)
        scrollView.hasVerticalScroller = content > 640
        preferredContentSize = NSSize(width: 320, height: height)
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
        stack.addArrangedSubview(label(Lf("status.meta", snapshot.state.label, snapshot.model, tokens), size: 10, color: .tertiaryLabelColor))

        if Settings.shared.showSessions && snapshot.sessions.count > 1 {
            stack.addArrangedSubview(label(L("sessions.header"), size: 10, weight: .semibold, color: .secondaryLabelColor))
            for session in snapshot.sessions.prefix(8) {
                let row = NSButton(title: session.state.label + " — " + session.title,
                                   target: self, action: #selector(sessionTapped(_:)))
                row.isBordered = false
                row.alignment = .left
                row.font = .systemFont(ofSize: 11)
                row.contentTintColor = session.id == snapshot.activeSessionId ? .labelColor : .secondaryLabelColor
                row.identifier = NSUserInterfaceItemIdentifier(session.id)
                row.widthAnchor.constraint(equalToConstant: 292).isActive = true
                stack.addArrangedSubview(row)
            }
        }

        if let group = snapshot.questionGroups.first {
            renderQuestion(group)
        }

        if !snapshot.approvalItems.isEmpty {
            renderApproval()
        }

        let actions = NSStackView(views: [button(L("action.open"), action: #selector(openTapped))])
        actions.orientation = .horizontal
        actions.spacing = 8
        if snapshot.busy {
            actions.addArrangedSubview(button(L("action.stop"), action: #selector(stopTapped)))
        }
        stack.addArrangedSubview(actions)
    }

    // MARK: - Question composer

    private func renderQuestion(_ group: BarQuestionGroup) {
        optionButtons = []
        customFields = []
        for question in group.questions {
            if let header = question.header, !header.isEmpty {
                stack.addArrangedSubview(label(header, size: 10, weight: .semibold, color: .secondaryLabelColor))
            }
            stack.addArrangedSubview(label(question.question, size: 12, weight: .medium))
            if let detail = question.detail, !detail.isEmpty {
                stack.addArrangedSubview(label(detail, size: 10, color: .secondaryLabelColor))
            }

            var buttons: [NSButton] = []
            if let options = question.options, !options.isEmpty {
                let optionsStack = NSStackView()
                optionsStack.orientation = .vertical
                optionsStack.alignment = .leading
                optionsStack.spacing = 2
                for option in options {
                    let choice: NSButton
                    if question.multiSelect == true {
                        choice = NSButton(checkboxWithTitle: option.label, target: nil, action: nil)
                    } else {
                        choice = NSButton(radioButtonWithTitle: option.label, target: nil, action: nil)
                    }
                    choice.font = .systemFont(ofSize: 11)
                    if let description = option.description, !description.isEmpty {
                        choice.toolTip = description
                    }
                    optionsStack.addArrangedSubview(choice)
                    buttons.append(choice)
                }
                stack.addArrangedSubview(optionsStack)
            }
            optionButtons.append(buttons)

            let custom = NSTextField()
            custom.placeholderString = L("question.custom")
            custom.font = .systemFont(ofSize: 11)
            custom.widthAnchor.constraint(equalToConstant: 280).isActive = true
            stack.addArrangedSubview(custom)
            customFields.append(custom)
        }
        let send = button(L("question.send"), action: #selector(sendAnswerTapped))
        sendButton = send
        stack.addArrangedSubview(send)
    }

    /// Test hook: drives the real controls (radio/checkbox click + Send click),
    /// so an end-to-end test answers through the popover code path.
    func autoAnswerFirstOption() {
        for buttons in optionButtons {
            buttons.first?.performClick(nil)
        }
        sendButton?.performClick(nil)
    }

    @objc private func sendAnswerTapped() {
        guard let group = snapshot.questionGroups.first else { return }
        let choices = group.questions.enumerated().map { index, _ in
            AnswerBatch.Choice(
                selected: index < optionButtons.count
                    ? optionButtons[index].filter { $0.state == .on }.map { $0.title }
                    : [],
                custom: index < customFields.count ? customFields[index].stringValue : ""
            )
        }
        onAnswer(group.id, AnswerBatch.build(group, choices: choices))
    }

    // MARK: - Approvals

    private func renderApproval() {
        let items = snapshot.approvalItems
        approvalIndex = min(max(0, approvalIndex), items.count - 1)
        let approval = items[approvalIndex]
        let suffix = items.count > 1 ? " " + Lf("approval.count", approvalIndex + 1, items.count) : ""
        let reason = approval.reason.map { " — " + $0 } ?? ""
        stack.addArrangedSubview(label(L("approval.label") + suffix + ": " + approval.toolName + reason, size: 11, color: .systemOrange))
        let row = NSStackView(views: [
            button(L("action.approve"), action: #selector(approveTapped)),
            button(L("action.deny"), action: #selector(denyTapped)),
        ])
        row.orientation = .horizontal
        row.spacing = 8
        if items.count > 1 {
            row.addArrangedSubview(button(L("action.previous"), action: #selector(previousApproval)))
            row.addArrangedSubview(button(L("action.next"), action: #selector(nextApproval)))
        }
        stack.addArrangedSubview(row)
    }

    @objc private func previousApproval() {
        approvalIndex = max(0, approvalIndex - 1)
        render()
    }

    @objc private func nextApproval() {
        approvalIndex = min(snapshot.approvalItems.count - 1, approvalIndex + 1)
        render()
    }

    @objc private func approveTapped() {
        guard approvalIndex < snapshot.approvalItems.count else { return }
        onApprove(snapshot.approvalItems[approvalIndex].id)
    }

    @objc private func denyTapped() {
        guard approvalIndex < snapshot.approvalItems.count else { return }
        onDeny(snapshot.approvalItems[approvalIndex].id)
    }

    @objc private func sessionTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onFocus(id)
    }

    @objc private func openTapped() { onOpen() }
    @objc private func stopTapped() { onStop() }
    @objc private func quitTapped() { onQuit() }
}
