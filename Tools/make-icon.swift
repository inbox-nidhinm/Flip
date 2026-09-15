import AppKit
import CoreGraphics
import Foundation

// Composes a macOS .icns from a single square image.
//
//   swift Tools/make-icon.swift Icon/source.png Resources/AppIcon.icns
//
// The artwork is written full-bleed, with no rounding, inset or shadow of its
// own. Current macOS masks app icons into the system shape and draws the
// background and shadow itself, so artwork that arrives pre-rounded and inset
// gets treated a second time and ends up as a small picture floating inside a
// large empty tile. Hand it a plain square and let the system do the shaping.

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <input.png> <output.icns>\n".utf8))
    exit(1)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

let canvas: CGFloat = 1024

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let source = NSImage(contentsOf: input),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("could not read \(input.path)")
}

if sourceCG.width < 1024 {
    FileHandle.standardError.write(Data(
        "note: source is \(sourceCG.width)x\(sourceCG.height); 1024x1024 gives a sharper large icon\n".utf8))
}

func context(_ size: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("could not allocate a \(size)x\(size) context")
    }
    ctx.interpolationQuality = .high
    return ctx
}

// -- master ------------------------------------------------------------------

let ctx = context(Int(canvas))

// Aspect-fill, so a non-square source is centre-cropped rather than squashed.
let scale = max(canvas / CGFloat(sourceCG.width), canvas / CGFloat(sourceCG.height))
let drawn = CGSize(width: CGFloat(sourceCG.width) * scale, height: CGFloat(sourceCG.height) * scale)
ctx.draw(sourceCG, in: CGRect(x: canvas / 2 - drawn.width / 2,
                              y: canvas / 2 - drawn.height / 2,
                              width: drawn.width, height: drawn.height))

guard let master = ctx.makeImage() else { fail("could not compose the master image") }

// -- iconset -----------------------------------------------------------------

let iconset = output.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
                           (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

for (points, scale) in slots {
    let pixels = points * scale
    let c = context(pixels)
    c.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let image = c.makeImage() else { fail("could not resample to \(pixels)px") }

    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let url = iconset.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("could not write \(name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("could not finalise \(name)") }
}

// -- icns --------------------------------------------------------------------

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fail("iconutil failed") }

try? FileManager.default.removeItem(at: iconset)
print("wrote \(output.lastPathComponent)")
