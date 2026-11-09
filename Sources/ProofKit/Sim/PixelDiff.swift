import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// How two screenshots of the same screen differ pixel by pixel: the share of pixels that changed, the box
/// around them, and an image with the changes in red over a faded copy of the new screenshot.
/// The status bar is left out (its clock changes between runs), and tiny colour shifts from anti-aliasing
/// don't count.
public struct PixelDiffResult: Codable, Equatable {
    public let changedPercent: Double      // of the compared area, 0…100
    public let box: [Int]?                 // x, y, width, height in pixels, nil when nothing changed
    public var image: String? = nil        // the highlighted diff image
    public var sizeMismatch: Bool = false  // different sizes (another device): not compared

    public var text: String {
        if sizeMismatch { return "pixels: not compared, the screenshots have different sizes" }
        guard let box else { return "pixels: no changes" }
        return String(format: "pixels: %.1f%% changed", changedPercent)
            + " (box \(box[0]),\(box[1]) \(box[2])x\(box[3]))" + (image.map { " → \($0)" } ?? "")
    }
}

public enum PixelDiff {
    /// Per-channel difference below this is noise.
    static let threshold = 24
    /// Share of the height at the top left out: the status bar.
    static let statusBarShare = 0.065

    /// Compares two RGBA8 buffers of the same size. Pure, so it's tested without images.
    public static func compare(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, skipTop: Int)
        -> (changed: Int, compared: Int, box: [Int]?, mask: [Bool]) {
        var mask = [Bool](repeating: false, count: width * height)
        var changed = 0
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in skipTop..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
                if d > threshold {
                    mask[y * width + x] = true
                    changed += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        let box = maxX < 0 ? nil : [minX, minY, maxX - minX + 1, maxY - minY + 1]
        return (changed, width * (height - skipTop), box, mask)
    }

    /// Compares two PNG files and, when they differ, writes the highlighted image to `output`.
    /// Nil when the images can't be read (or on a platform without CoreGraphics).
    public static func diff(before: String, after: String, output: String) -> PixelDiffResult? {
        #if canImport(CoreGraphics) && canImport(ImageIO)
        guard let a = load(before), let b = load(after) else { return nil }
        guard a.width == b.width, a.height == b.height else {
            return PixelDiffResult(changedPercent: 0, box: nil, sizeMismatch: true)
        }
        let skip = Int(Double(a.height) * statusBarShare)
        let r = compare(a.pixels, b.pixels, width: a.width, height: a.height, skipTop: skip)
        var result = PixelDiffResult(changedPercent: r.compared == 0 ? 0 : Double(r.changed) / Double(r.compared) * 100, box: r.box)
        try? FileManager.default.removeItem(atPath: output)
        if r.box != nil, write(highlight(b.pixels, mask: r.mask), width: a.width, height: a.height, to: output) {
            result.image = output
        }
        return result
        #else
        return nil
        #endif
    }

    /// The new screenshot faded to grey, with changed pixels in red.
    static func highlight(_ pixels: [UInt8], mask: [Bool]) -> [UInt8] {
        var out = pixels
        for p in 0..<mask.count {
            let i = p * 4
            if mask[p] {
                out[i] = 255; out[i + 1] = 0; out[i + 2] = 0
            } else {
                let grey = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
                let faded = UInt8(min(255, 170 + grey / 3))
                out[i] = faded; out[i + 1] = faded; out[i + 2] = faded
            }
            out[i + 3] = 255
        }
        return out
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    static func load(_ path: String) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (pixels, w, h) : nil
    }

    static func write(_ pixels: [UInt8], width: Int, height: Int, to path: String) -> Bool {
        var copy = pixels
        return copy.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(dest, image, nil)
            return CGImageDestinationFinalize(dest)
        }
    }
    #endif
}
