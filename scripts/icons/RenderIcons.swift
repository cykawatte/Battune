import AppKit

@main @MainActor struct RenderIcons {
  static func main() throws {
    let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    for helper in [false, true] {
      let name = helper ? "BattuneHelper" : "Battune"
      let folder = destination.appendingPathComponent("\(name).iconset")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
          let pixels = size * scale
          guard
            let bitmap = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
          else { throw CocoaError(.fileWriteUnknown) }
          NSGraphicsContext.saveGraphicsState()
          NSGraphicsContext.current = context
          let transform = NSAffineTransform()
          transform.scale(by: CGFloat(pixels) / 1024)
          transform.concat()
          let tile = NSBezierPath(
            roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
          let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.075, alpha: 1),
            ending: NSColor(calibratedRed: 0.17, green: 0.22, blue: 0.28, alpha: 1))
          gradient?.draw(in: tile, angle: 75)
          NSColor(white: 1, alpha: 0.10).setStroke()
          tile.lineWidth = 3
          tile.stroke()
          NSGraphicsContext.saveGraphicsState()
          let mark = NSAffineTransform()
          mark.translateX(by: 227, yBy: 800)
          mark.scaleX(by: 23, yBy: -23)
          mark.concat()
          NSColor(white: 0.98, alpha: 1).setFill()
          BattuneMark.drawSymbol()
          NSGraphicsContext.restoreGraphicsState()
          if helper {
            let badge = NSBezierPath(
              roundedRect: NSRect(x: 690, y: 120, width: 192, height: 192), xRadius: 58, yRadius: 58
            )
            NSColor(calibratedRed: 0.26, green: 0.65, blue: 0.68, alpha: 1).setFill()
            badge.fill()
            let shield = NSBezierPath()
            shield.move(to: NSPoint(x: 786, y: 270))
            shield.line(to: NSPoint(x: 836, y: 250))
            shield.line(to: NSPoint(x: 832, y: 207))
            shield.curve(
              to: NSPoint(x: 786, y: 167), controlPoint1: NSPoint(x: 828, y: 185),
              controlPoint2: NSPoint(x: 798, y: 174))
            shield.curve(
              to: NSPoint(x: 740, y: 207), controlPoint1: NSPoint(x: 774, y: 174),
              controlPoint2: NSPoint(x: 744, y: 185))
            shield.line(to: NSPoint(x: 736, y: 250))
            shield.close()
            NSColor.white.setStroke()
            shield.lineWidth = 10
            shield.stroke()
          }
          NSGraphicsContext.restoreGraphicsState()
          guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
          }
          let suffix = scale == 2 ? "@2x" : ""
          try png.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
          if pixels == 1024 { try png.write(to: destination.appendingPathComponent("\(name).png")) }
        }
      }
    }
  }
}
