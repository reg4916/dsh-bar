import AppKit

/// Top-anchored document view for the popover's scroll view.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
