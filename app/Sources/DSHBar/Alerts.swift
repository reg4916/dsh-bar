import AppKit

/// In-app fallback for builds macOS refuses to register with Notification
/// Center: a floating card near the menu bar with the same actions.
final class AlertPresenter {
    var onOpen: (() -> Void)?
    var onDeny: ((String) -> Void)?

    private var panel: NSPanel?
    private var timer: Timer?

    func approval(id: String, tool: String, reason: String?) {
        present(
            title: Lf("notify.approval.title", tool),
            body: reason ?? L("alert.approval.body"),
            actions: [(L("action.open"), { [weak self] in self?.onOpen?() }),
                      (L("action.deny"), { [weak self] in self?.onDeny?(id) })],
            autoDismiss: false
        )
    }

    func question(title: String, text: String) {
        present(
            title: Lf("notify.question.title", title),
            body: text,
            actions: [(L("action.open"), { [weak self] in self?.onOpen?() })],
            autoDismiss: false
        )
    }

    func done(title: String) {
        present(title: L("notify.done.title"), body: title,
                actions: [(L("action.open"), { [weak self] in self?.onOpen?() })],
                autoDismiss: true)
    }

    func error(_ text: String) {
        present(title: L("notify.error.title"), body: text,
                actions: [(L("action.open"), { [weak self] in self?.onOpen?() })],
                autoDismiss: true)
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(title: String, body: String,
                         actions: [(String, () -> Void)], autoDismiss: Bool) {
        dismiss()
        NSSound(named: "Glass")?.play()

        let width: CGFloat = 340
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 120))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .labelColor
        stack.addArrangedSubview(titleField)

        let bodyField = NSTextField(labelWithString: body)
        bodyField.font = .systemFont(ofSize: 11)
        bodyField.textColor = .secondaryLabelColor
        bodyField.lineBreakMode = .byWordWrapping
        bodyField.maximumNumberOfLines = 3
        bodyField.widthAnchor.constraint(equalToConstant: width - 28).isActive = true
        stack.addArrangedSubview(bodyField)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        for (label, action) in actions {
            let button = ClosureButton(title: label, action: action)
            row.addArrangedSubview(button)
        }
        row.addArrangedSubview(ClosureButton(title: L("action.dismiss"), action: { [weak self] in self?.dismiss() }))
        stack.addArrangedSubview(row)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])

        let size = effect.fittingSize
        effect.frame = NSRect(x: 0, y: 0, width: width, height: max(96, size.height))

        let panel = NSPanel(contentRect: effect.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = effect
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - width - 16, y: frame.maxY - effect.frame.height - 12))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        self.panel = panel

        if autoDismiss {
            timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
    }
}

/// NSButton that owns its closure, so the card needs no selector plumbing.
final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .rounded
        self.controlSize = .small
        self.target = self
        self.action = #selector(fire)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() { handler() }
}
