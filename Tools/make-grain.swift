// Prepares the panel grain from its source artwork.
//
//     swift Tools/make-grain.swift <source.png> Sources/Flip/Textures/grain.png
//
// Two things happen here, both so the texture can be *tiled* at native
// resolution rather than fitted to a panel.
//
// The width is cropped to an even number of pixels. The grain is treated as a
// 2× asset, so its point size is half its pixel size, and an odd width would
// put every tile boundary on a half-point — invisible on Retina, a seam at 1×.
// One column of random noise is not a loss.
//
// Nothing is rescaled. The artwork peaks at 96 of 255 alpha and that *is* the
// artwork — it is drawn source-over, so the alpha it was authored with is the
// weight it was authored at, and `FlipTheme.grain` scales down from there.
// (An earlier pass normalised the peak to full scale. That was compensation for
// a blend mode this no longer uses, and it made the grain heavier than drawn.)
//
// The four channels are folded to two. The source is measurably neutral
// (R = G = B on every sample, mean channel spread 0.000), so three colour
// channels carry one channel of information; grey + alpha says the same thing
// in half the bytes. Nothing is quantised — this is a lossless repack.
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-grain.swift <source.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let raw = img.dataProvider?.data,
      let d = CFDataGetBytePtr(raw) else {
    FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
// Even dimensions both ways, so one tile is a whole number of points at 2×.
let w = img.width - img.width % 2, h = img.height - img.height % 2
let bpr = img.bytesPerRow

var buf = [UInt8](repeating: 0, count: w * h * 2)
for y in 0..<h {
    for x in 0..<w {
        let p = y * bpr + x * 4, q = (y * w + x) * 2
        buf[q]     = UInt8((Int(d[p]) + Int(d[p + 1]) + Int(d[p + 2])) / 3)
        buf[q + 1] = d[p + 3]
    }
}

guard let provider = CGDataProvider(data: Data(buf) as CFData),
      let out = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 16,
                        bytesPerRow: w * 2, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider, decode: nil,
                        shouldInterpolate: false, intent: .defaultIntent),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                 "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write("cannot write \(args[2])\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("grain \(w)×\(h)px, alpha unchanged")
