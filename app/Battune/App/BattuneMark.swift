import AppKit

/// Vector interpretation of the supplied Battune B/slider mark. A template image
/// lets macOS provide contrast in light, dark and highlighted menu-bar states.
@MainActor enum BattuneMark {
  static let menuBarImage: NSImage = {
    let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
      NSColor.black.setFill()
      let transform = NSAffineTransform()
      transform.translateX(by: 1, yBy: 1)
      transform.scale(by: 0.75)
      transform.concat()

      let outline = NSBezierPath()
      outline.windingRule = .evenOdd
      outline.move(to: NSPoint(x: 8, y: 1))
      outline.curve(
        to: NSPoint(x: 1, y: 8), controlPoint1: NSPoint(x: 3, y: 1),
        controlPoint2: NSPoint(x: 1, y: 3))
      outline.line(to: NSPoint(x: 1, y: 17))
      outline.curve(
        to: NSPoint(x: 8, y: 24), controlPoint1: NSPoint(x: 1, y: 22),
        controlPoint2: NSPoint(x: 3, y: 24))
      outline.line(to: NSPoint(x: 16, y: 24))
      outline.curve(
        to: NSPoint(x: 22, y: 16), controlPoint1: NSPoint(x: 22, y: 24),
        controlPoint2: NSPoint(x: 23, y: 20))
      outline.line(to: NSPoint(x: 23, y: 16))
      outline.curve(
        to: NSPoint(x: 24, y: 15), controlPoint1: NSPoint(x: 24, y: 16),
        controlPoint2: NSPoint(x: 24, y: 16))
      outline.line(to: NSPoint(x: 24, y: 10))
      outline.curve(
        to: NSPoint(x: 23, y: 9), controlPoint1: NSPoint(x: 24, y: 9),
        controlPoint2: NSPoint(x: 24, y: 9))
      outline.line(to: NSPoint(x: 22, y: 9))
      outline.curve(
        to: NSPoint(x: 16, y: 1), controlPoint1: NSPoint(x: 23, y: 5),
        controlPoint2: NSPoint(x: 21, y: 1))
      outline.close()

      outline.move(to: NSPoint(x: 8, y: 3.4))
      outline.line(to: NSPoint(x: 16, y: 3.4))
      outline.curve(
        to: NSPoint(x: 19.2, y: 10), controlPoint1: NSPoint(x: 20.5, y: 3.4),
        controlPoint2: NSPoint(x: 21.5, y: 7.2))
      outline.curve(
        to: NSPoint(x: 19.2, y: 14.8), controlPoint1: NSPoint(x: 17.6, y: 11.6),
        controlPoint2: NSPoint(x: 21.4, y: 12.1))
      outline.curve(
        to: NSPoint(x: 16, y: 21.6), controlPoint1: NSPoint(x: 21.5, y: 18.5),
        controlPoint2: NSPoint(x: 20, y: 21.6))
      outline.line(to: NSPoint(x: 8, y: 21.6))
      outline.curve(
        to: NSPoint(x: 3.4, y: 17), controlPoint1: NSPoint(x: 4.6, y: 21.6),
        controlPoint2: NSPoint(x: 3.4, y: 20))
      outline.line(to: NSPoint(x: 3.4, y: 8))
      outline.curve(
        to: NSPoint(x: 8, y: 3.4), controlPoint1: NSPoint(x: 3.4, y: 4.6),
        controlPoint2: NSPoint(x: 4.6, y: 3.4))
      outline.close()
      outline.fill()
      NSBezierPath(
        roundedRect: NSRect(x: 10.1, y: 5.4, width: 2.1, height: 14.2), xRadius: 1.05, yRadius: 1.05
      ).fill()
      NSBezierPath(ovalIn: NSRect(x: 8.3, y: 9.6, width: 5.7, height: 5.7)).fill()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Battune"
    return image
  }()
}
