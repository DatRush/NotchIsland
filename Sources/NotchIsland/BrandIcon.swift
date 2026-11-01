import AppKit

// One vector master for the app, About window and template menu-bar symbol.
enum BrandIcon {
    static func image(size: CGFloat, template: Bool = false, background: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.scale(by: rect.width / 1024)
            transform.concat()
            if !template && background {
                NSColor(srgbRed: 61/255, green: 64/255, blue: 68/255, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210).fill()
            }
            (template ? NSColor.black : NSColor(srgbRed: 216/255, green: 215/255, blue: 210/255, alpha: 1)).setFill()
            let frame = NSBezierPath(roundedRect: NSRect(x: 160, y: 292, width: 704, height: 440), xRadius: 78, yRadius: 78)
            frame.append(NSBezierPath(roundedRect: NSRect(x: 206, y: 338, width: 612, height: 348), xRadius: 34, yRadius: 34))
            frame.windingRule = .evenOdd
            frame.fill()
            // Broad, shallow notch joined to the upper frame.
            let notch = NSBezierPath()
            notch.move(to: NSPoint(x: 376, y: 710))
            notch.line(to: NSPoint(x: 648, y: 710))
            notch.line(to: NSPoint(x: 648, y: 650))
            notch.curve(to: NSPoint(x: 620, y: 622), controlPoint1: NSPoint(x: 648, y: 632), controlPoint2: NSPoint(x: 638, y: 622))
            notch.line(to: NSPoint(x: 404, y: 622))
            notch.curve(to: NSPoint(x: 376, y: 650), controlPoint1: NSPoint(x: 386, y: 622), controlPoint2: NSPoint(x: 376, y: 632))
            notch.close()
            notch.fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "NotchIsland"
        return image
    }
}
