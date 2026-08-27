// Turns the pre-rounded app-icon master into a full-bleed, fully opaque
// square for the ICNS. macOS 26 applies its own Liquid Glass squircle mask
// to app icons, but only when every edge pixel is (nearly) opaque — any
// transparency at the edges triggers the shrunken gray-background "default
// treatment". So: measure the master's own corner rounding, zoom in just
// enough to push those transparent corners off the canvas, and emit an
// opaque PNG the system can mask itself.
//
// Usage: swift Tools/make_fullbleed_icon.swift <master.png> <out.png>
// Needs only the Command Line Tools (CoreGraphics/ImageIO).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: make_fullbleed_icon <master.png> <out.png>")
}
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fail("cannot read \(inputURL.path)") }

let width = image.width
let height = image.height
guard width == height else { fail("master must be square, got \(width)x\(height)") }

// Read the alpha channel by drawing into a known RGBA layout.
guard let probe = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("cannot create probe context") }
probe.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let pixels = probe.data?.assumingMemoryBound(to: UInt8.self) else {
    fail("cannot read probe pixels")
}
func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

// First opaque column at the vertical middle = outer transparent margin m;
// first opaque column on the top row ≈ m + corner radius r.
func firstOpaqueX(row: Int) -> Int {
    for x in 0..<width where alpha(x, row) >= 250 { return x }
    return width
}
let margin = firstOpaqueX(row: height / 2)
// The topmost row containing art: a rounded rect spans [m+r, W-m-r] there.
var topRow = 0
while topRow < height, firstOpaqueX(row: topRow) == width { topRow += 1 }
let cornerReach = firstOpaqueX(row: topRow)
let radius = max(cornerReach - margin, 0)
guard margin < width / 4 else { fail("no opaque art found") }

// A radius-r corner is transparent up to r(1-1/sqrt2) ≈ 0.293r diagonally;
// crop a bit deeper than that (plus the margin) to clear anti-aliasing.
let inset = margin + Int((Double(radius) * 0.35).rounded(.up))
let scale = Double(width) / Double(width - 2 * inset)

guard let canvas = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fail("cannot create output context") }
canvas.interpolationQuality = .high
let scaled = Double(width) * scale
let offset = (scaled - Double(width)) / 2
canvas.draw(image, in: CGRect(x: -offset, y: -offset, width: scaled, height: scaled))

guard let flattened = canvas.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fail("cannot create \(outputURL.path)") }
CGImageDestinationAddImage(dest, flattened, nil)
guard CGImageDestinationFinalize(dest) else { fail("cannot write \(outputURL.path)") }
print("wrote \(outputURL.path) (margin \(margin), radius \(radius), inset \(inset))")
