import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var timer: Timer?
    private var frame = 0
    private var tick = 0
    private var stateIndex = 0
    private var snapshot = BarSnapshot.demo[0]

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        startTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
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
        popover.contentViewController = StatusViewController(snapshot: snapshot, onOpen: { [weak self] in
            self?.openDSH()
        }, onQuit: {
            NSApplication.shared.terminate(nil)
        })
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.onFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func onFrame() {
        tick += 1
        frame += 1

        // M1 demo sequencer: advance every 2.5 s so every state is visible.
        if tick % 30 == 0 {
            stateIndex = (stateIndex + 1) % BarSnapshot.demo.count
            snapshot = BarSnapshot.demo[stateIndex]
            (popover.contentViewController as? StatusViewController)?.update(snapshot)
        }

        statusItem.button?.image = WhaleIcon.image(frame: frame, state: snapshot.state)
        updateBadge()
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        if snapshot.approvals > 0 {
            let dot = NSMutableAttributedString(string: "\u{2009}\u{25CF}")
            dot.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: dot.length))
            dot.addAttribute(.font, value: NSFont.systemFont(ofSize: 9, weight: .bold), range: NSRange(location: 0, length: dot.length))
            button.attributedTitle = dot
        } else {
            button.attributedTitle = NSAttributedString(string: "")
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
        menu.addItem(withTitle: "Open DSH", action: #selector(openDSH), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        login.state = .off
        login.isEnabled = false
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DSH Bar", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDSH() {
        let raw = ProcessInfo.processInfo.environment["DSH_BAR_URL"] ?? "http://127.0.0.1:49399"
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// Minimal popover content for M1. M2 replaces the hard-coded fields with the
/// live snapshot stream from the host plugin.
final class StatusViewController: NSViewController {
    private var snapshot: BarSnapshot
    private let titleLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let onOpen: () -> Void
    private let onQuit: () -> Void

    init(snapshot: BarSnapshot, onOpen: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onOpen = onOpen
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 148))

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        stateLabel.font = .systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.lineBreakMode = .byTruncatingTail
        metaLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        metaLabel.textColor = .tertiaryLabelColor

        let openButton = NSButton(title: "Open DSH", target: self, action: #selector(openTapped))
        openButton.bezelStyle = .rounded
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitTapped))
        quitButton.bezelStyle = .rounded

        let stack = NSStackView(views: [titleLabel, stateLabel, metaLabel, openButton, quitButton])
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
            container.widthAnchor.constraint(equalToConstant: 300),
        ])

        view = container
        update(snapshot)
    }

    func update(_ snapshot: BarSnapshot) {
        self.snapshot = snapshot
        guard isViewLoaded else { return }
        titleLabel.stringValue = snapshot.title
        stateLabel.stringValue = snapshot.detail.isEmpty ? snapshot.state.label : snapshot.detail
        let tokens = NumberFormatter.localizedString(from: NSNumber(value: snapshot.tokens), number: .decimal)
        metaLabel.stringValue = "\(snapshot.state.label) · \(snapshot.model) · \(tokens) tok · \(snapshot.cost)"
    }

    @objc private func openTapped() { onOpen() }
    @objc private func quitTapped() { onQuit() }
}
