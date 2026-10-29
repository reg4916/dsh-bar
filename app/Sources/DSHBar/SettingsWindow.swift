import AppKit

extension Notification.Name {
    static let dshBarSettingsChanged = Notification.Name("dshBarSettingsChanged")
}

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let controller = SettingsViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = L("settings.title")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 360))
        window.center()
        self.init(window: window)
    }
}

final class SettingsViewController: NSViewController {
    private var pendingTag: String?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 360))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        stack.addArrangedSubview(title(L("settings.title"), size: 15, weight: .semibold))
        stack.addArrangedSubview(check(L("settings.notifications"), Settings.shared.notificationsEnabled, #selector(toggleNotifications)))
        stack.addArrangedSubview(check(L("settings.animate"), Settings.shared.animateIcon, #selector(toggleAnimate)))
        stack.addArrangedSubview(check(L("settings.sessions"), Settings.shared.showSessions, #selector(toggleSessions)))
        stack.addArrangedSubview(hint(L("settings.reduceMotionHint")))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(check(L("settings.launchAtLogin"), LaunchAgent.enabled, #selector(toggleLaunch)))
        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(title(Lf("settings.version", UpdateChecker.currentVersion), size: 11, color: .secondaryLabelColor))
        let updates = NSStackView()
        updates.orientation = .horizontal
        updates.spacing = 10
        let checkButton = NSButton(title: L("settings.checkUpdates"), target: self, action: #selector(checkUpdates))
        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .small
        updates.addArrangedSubview(checkButton)
        let label = hint(L("settings.upToDate"))
        label.identifier = NSUserInterfaceItemIdentifier("updateLabel")
        updates.addArrangedSubview(label)
        stack.addArrangedSubview(updates)

        view = container
    }

    private func title(_ text: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func hint(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 10)
        field.textColor = .tertiaryLabelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 2
        field.widthAnchor.constraint(equalToConstant: 340).isActive = true
        return field
    }

    private func check(_ text: String, _ on: Bool, _ action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: text, target: self, action: action)
        button.state = on ? .on : .off
        button.font = .systemFont(ofSize: 12)
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 344).isActive = true
        return box
    }

    private func changed() {
        NotificationCenter.default.post(name: .dshBarSettingsChanged, object: nil)
    }

    @objc private func toggleNotifications(_ sender: NSButton) {
        Settings.shared.notificationsEnabled = sender.state == .on
        changed()
    }

    @objc private func toggleAnimate(_ sender: NSButton) {
        Settings.shared.animateIcon = sender.state == .on
        changed()
    }

    @objc private func toggleSessions(_ sender: NSButton) {
        Settings.shared.showSessions = sender.state == .on
        changed()
    }

    @objc private func toggleLaunch(_ sender: NSButton) {
        LaunchAgent.setEnabled(sender.state == .on)
        changed()
    }

    @objc private func checkUpdates() {
        guard let label = view.subviewsRecursive().compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "updateLabel" }) else { return }
        label.stringValue = L("settings.checking")
        UpdateChecker.check { [weak self, weak label] tag in
            guard let self, let label else { return }
            if let tag {
                self.pendingTag = tag
                label.stringValue = Lf("settings.updateAvailable", tag)
            } else {
                label.stringValue = L("settings.upToDate")
            }
        }
    }
}

private extension NSView {
    func subviewsRecursive() -> [NSView] {
        subviews + subviews.flatMap { $0.subviewsRecursive() }
    }
}
