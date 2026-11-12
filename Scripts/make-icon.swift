// Generates App/AppIcon.icon, the Icon Composer document for the app icon:
// a white ⌘-style glyph over an indigo automatic gradient. Xcode 26+ compiles
// it into the layered Liquid Glass icon and fallbacks for earlier macOS.
//
// Usage: swift Scripts/make-icon.swift
// Preview: ictool App/AppIcon.icon --export-image --output-file icon.png \
//          --platform macOS --rendition Default --width 512 --height 512 --scale 2
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/AppIcon.icon")
let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// Glyph layer: 1024×1024, transparent, white glyph centered.
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let glyph = "⌘" as NSString
var font = NSFont.systemFont(ofSize: 560, weight: .semibold)
if let rounded = font.fontDescriptor.withDesign(.rounded), let roundedFont = NSFont(descriptor: rounded, size: 560) {
    font = roundedFont
}
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let bounds = glyph.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin, .usesDeviceMetrics], attributes: attributes)
// `draw(at:)` places the line fragment's bottom-left corner, which sits one
// descender below the baseline that `bounds` is measured from.
let origin = NSPoint(
    x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
    y: (CGFloat(size) - bounds.height) / 2 - bounds.minY + font.descender
)
glyph.draw(at: origin, withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
try png.write(to: assets.appendingPathComponent("glyph.png"))

let document = """
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:0.38039,0.37647,0.94118,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "glyph.png",
          "name" : "glyph",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""
try document.write(to: root.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(root.path)")
