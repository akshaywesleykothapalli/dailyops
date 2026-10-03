// Renders the official DailyOps macOS app icon:
// Centers the DailyOps mark inside a standard macOS squircle (824pt in 1024pt canvas, radius 185pt)
// and generates both the Xcode asset catalog (Assets.xcassets/AppIcon.appiconset) and AppIcon.icns.
import AppKit

let canvasSize: CGFloat = 1024
let artSize: CGFloat = 824
let artOrigin: CGFloat = (canvasSize - artSize) / 2 // 100
let cornerRadius: CGFloat = 185

let sourceURL = URL(fileURLWithPath: "Branding/DailyOps-Dark.png")
guard let sourceImage = NSImage(contentsOf: sourceURL),
      let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not load Branding/DailyOps-Dark.png")
}

// In Branding/DailyOps-Dark.png (1254x1254), the symbol is centered at (643.5, 617.0).
// Crop window of 960x960 perfectly frames the mark with ~145pt padding inside the squircle.
let cropSize: CGFloat = 960
let cx: CGFloat = 643.5
let cy: CGFloat = 617.0
let cropRect = CGRect(x: cx - cropSize / 2, y: cy - cropSize / 2, width: cropSize, height: cropSize)

guard let croppedCG = cgImage.cropping(to: cropRect) else {
    fatalError("Failed to crop source image")
}

// Draw master 1024x1024 icon
let ctx = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let squircleRect = CGRect(x: artOrigin, y: artOrigin, width: artSize, height: artSize)
let squirclePath = CGPath(
    roundedRect: squircleRect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

// Draw in CoreGraphics coordinates; an extra flip would invert the supplied mark.
ctx.interpolationQuality = .high
ctx.draw(croppedCG, in: squircleRect)
ctx.restoreGState()

guard let masterImage = ctx.makeImage() else {
    fatalError("Failed to create master CGImage")
}

func savePNG(cgImage: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Failed to create CGImageDestination for \(url)")
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Failed to write PNG at \(url.path)")
    }
}

func resize(image: CGImage, to size: Int) -> CGImage {
    let resizeCtx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    resizeCtx.interpolationQuality = .high
    resizeCtx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return resizeCtx.makeImage()!
}

// 1. Prepare asset catalog
let appIconSetDir = URL(fileURLWithPath: "DailyOpsApp/Resources/Assets.xcassets/AppIcon.appiconset")
let xcassetsDir = URL(fileURLWithPath: "DailyOpsApp/Resources/Assets.xcassets")
try FileManager.default.createDirectory(at: appIconSetDir, withIntermediateDirectories: true)

let xcassetsContents = """
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""
try xcassetsContents.write(to: xcassetsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let specs: [(String, Int, String, String)] = [
    ("icon_16x16.png", 16, "16x16", "1x"),
    ("icon_16x16@2x.png", 32, "16x16", "2x"),
    ("icon_32x32.png", 32, "32x32", "1x"),
    ("icon_32x32@2x.png", 64, "32x32", "2x"),
    ("icon_128x128.png", 128, "128x128", "1x"),
    ("icon_128x128@2x.png", 256, "128x128", "2x"),
    ("icon_256x256.png", 256, "256x256", "1x"),
    ("icon_256x256@2x.png", 512, "256x256", "2x"),
    ("icon_512x512.png", 512, "512x512", "1x"),
    ("icon_512x512@2x.png", 1024, "512x512", "2x"),
]

var imagesEntries: [String] = []
for (name, px, size, scale) in specs {
    let resized = resize(image: masterImage, to: px)
    savePNG(cgImage: resized, to: appIconSetDir.appendingPathComponent(name))
    imagesEntries.append("""
        {
          "filename": "\(name)",
          "idiom": "mac",
          "scale": "\(scale)",
          "size": "\(size)"
        }
    """)
}

let appIconContents = """
{
  "images": [
\(imagesEntries.joined(separator: ",\n"))
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""
try appIconContents.write(to: appIconSetDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("Generated Assets.xcassets/AppIcon.appiconset with \(specs.count) variants.")
