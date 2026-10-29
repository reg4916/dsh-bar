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
        let bob: CGFloat = animates ? sin(t * .pi * 2) * 0.7 : 0
        let tail: CGFloat = animates ? sin(t * .pi * 2) * 0.9 : 0.25
        NSColor.black.setFill()

        // Body.
        NSBezierPath(ovalIn: NSRect(x: 5.2, y: 7.0 + bob, width: 12.0, height: 8.2)).fill()

        // Tail: two flukes swinging around the body's left end.
        let tailPath = NSBezierPath()
        tailPath.move(to: NSPoint(x: 6.0, y: 11.0 + bob))
        tailPath.line(to: NSPoint(x: 1.6, y: 11.0 + bob + 4.0 * tail + 1.2))
        tailPath.line(to: NSPoint(x: 3.0, y: 11.0 + bob))
        tailPath.line(to: NSPoint(x: 1.6, y: 11.0 + bob - 4.0 * tail - 1.2))
        tailPath.close()
        tailPath.fill()

        // Fin.
        let fin = NSBezierPath()
        fin.move(to: NSPoint(x: 10.2, y: 8.6 + bob))
        fin.line(to: NSPoint(x: 12.4, y: 5.6 + bob))
        fin.line(to: NSPoint(x: 13.2, y: 8.8 + bob))
        fin.close()
        fin.fill()

        // Spout while the agent is busy.
        if state == .thinking || state == .tool {
            for index in 0..<3 {
                let lift = CGFloat((frame / 3 + index * 2) % 6) * 0.9
                let drop = NSBezierPath(ovalIn: NSRect(x: 12.4 + CGFloat(index) * 2.1, y: 16.0 + lift + bob, width: 1.7, height: 1.7))
                drop.fill()
            }
        }

        // Eye: punch a hole so the template adapts to the menu bar tint.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 13.6, y: 10.6 + bob, width: 2.1, height: 2.1)).fill()
        NSGraphicsContext.restoreGraphicsState()
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
