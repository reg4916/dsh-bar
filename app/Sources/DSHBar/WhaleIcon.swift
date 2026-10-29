import AppKit

/// Draws the whale mark used in the menu bar.
///
/// The image is a template (black + alpha) so macOS recolours it for light and
/// dark menu bars. Animation re-renders frames at runtime: no sprite sheet, no
/// asset pipeline, one source of truth.
enum WhaleIcon {
    static let pointSize: CGFloat = 22

    static func image(frame: Int, state: BarState) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            drawWhale(in: rect, frame: frame, state: state)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawWhale(in rect: NSRect, frame: Int, state: BarState) {
        let t = CGFloat(frame) / 12.0
        let animates = state.animates
        let bob: CGFloat = animates ? sin(t * .pi * 2) * 0.6 : 0
        let tail: CGFloat = animates ? sin(t * .pi * 2) * 1.0 : 0.2
        NSColor.black.setFill()

        // Head at the left, back curving up to a single raised fluke on the
        // right. A whale tail is a broad blade, not a fish's forked fin.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 2.6, y: 8.8 + bob))
        body.curve(to: NSPoint(x: 5.0, y: 14.6 + bob),
                   controlPoint1: NSPoint(x: 2.0, y: 11.8 + bob),
                   controlPoint2: NSPoint(x: 3.0, y: 14.0 + bob))
        body.curve(to: NSPoint(x: 14.8, y: 13.6 + bob),
                   controlPoint1: NSPoint(x: 8.2, y: 15.0 + bob),
                   controlPoint2: NSPoint(x: 12.0, y: 14.6 + bob))
        body.curve(to: NSPoint(x: 19.0, y: 17.6 + bob + tail),
                   controlPoint1: NSPoint(x: 16.4, y: 14.6 + bob),
                   controlPoint2: NSPoint(x: 17.8, y: 16.2 + bob))
        body.curve(to: NSPoint(x: 20.0, y: 14.8 + bob + tail * 0.4),
                   controlPoint1: NSPoint(x: 19.7, y: 16.9 + bob + tail),
                   controlPoint2: NSPoint(x: 20.2, y: 15.8 + bob + tail * 0.4))
        body.curve(to: NSPoint(x: 17.2, y: 12.4 + bob),
                   controlPoint1: NSPoint(x: 19.4, y: 13.8 + bob),
                   controlPoint2: NSPoint(x: 18.2, y: 12.8 + bob))
        body.curve(to: NSPoint(x: 11.0, y: 6.2 + bob),
                   controlPoint1: NSPoint(x: 15.0, y: 9.0 + bob),
                   controlPoint2: NSPoint(x: 12.8, y: 7.2 + bob))
        body.curve(to: NSPoint(x: 4.4, y: 6.4 + bob),
                   controlPoint1: NSPoint(x: 8.0, y: 5.2 + bob),
                   controlPoint2: NSPoint(x: 5.6, y: 5.4 + bob))
        body.curve(to: NSPoint(x: 2.6, y: 8.8 + bob),
                   controlPoint1: NSPoint(x: 3.4, y: 7.0 + bob),
                   controlPoint2: NSPoint(x: 2.4, y: 8.0 + bob))
        body.close()
        body.fill()

        // Pectoral flipper.
        let fin = NSBezierPath()
        fin.move(to: NSPoint(x: 9.0, y: 7.4 + bob))
        fin.curve(to: NSPoint(x: 6.0, y: 3.8 + bob),
                  controlPoint1: NSPoint(x: 7.6, y: 6.4 + bob),
                  controlPoint2: NSPoint(x: 6.4, y: 4.6 + bob))
        fin.curve(to: NSPoint(x: 10.6, y: 7.0 + bob),
                  controlPoint1: NSPoint(x: 7.4, y: 5.0 + bob),
                  controlPoint2: NSPoint(x: 9.2, y: 6.0 + bob))
        fin.close()
        fin.fill()

        // Mouth and eye: punch holes so the template adapts to the bar tint.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSColor.white.setStroke()
        let jaw = NSBezierPath()
        jaw.move(to: NSPoint(x: 2.8, y: 8.0 + bob))
        jaw.curve(to: NSPoint(x: 7.4, y: 7.2 + bob),
                  controlPoint1: NSPoint(x: 4.2, y: 7.6 + bob),
                  controlPoint2: NSPoint(x: 6.0, y: 7.0 + bob))
        jaw.lineWidth = 0.55
        jaw.stroke()
        NSBezierPath(ovalIn: NSRect(x: 4.25, y: 10.25 + bob, width: 1.5, height: 1.5)).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Spout while the agent is busy.
        if state == .thinking || state == .tool {
            NSColor.black.setFill()
            for index in 0..<3 {
                let lift = CGFloat((frame / 3 + index * 2) % 6) * 0.5
                let drop = NSBezierPath(ovalIn: NSRect(x: 6.0 + CGFloat(index) * 1.5,
                                                       y: 15.8 + lift + bob,
                                                       width: 0.85, height: 0.85))
                drop.fill()
            }
        }
    }

    /// Minimal status dot for the "dot only" menu bar mode.
    static func dot(state: BarState) -> NSImage {
        let color: NSColor
        switch state {
        case .thinking, .tool: color = .systemBlue
        case .approval: color = .systemOrange
        case .done: color = .systemGreen
        case .error: color = .systemRed
        case .idle: color = .secondaryLabelColor
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
