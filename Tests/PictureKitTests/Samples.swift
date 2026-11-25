import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pictures drawn for the tests: no fixture files.
enum Samples {
    /// A gradient with noise, which compresses like a photo or a painted cover.
    static func photo(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        var seed: UInt32 = 42
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Int(seed >> 28)
                let i = y * context.bytesPerRow + x * 4
                pixels[i] = UInt8(min(255, x * 255 / width + noise))
                pixels[i + 1] = UInt8(min(255, y * 255 / height + noise))
                pixels[i + 2] = UInt8(min(255, 128 + noise))
                pixels[i + 3] = alpha ? (x < width / 2 ? 0 : 255) : 255
                if alpha && x < width / 2 { (pixels[i], pixels[i + 1], pixels[i + 2]) = (0, 0, 0) }
            }
        }
        return context.makeImage()!
    }

    static func flat(width: Int, height: Int, gray: CGFloat = 0.5) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Gray with transparency, the kind HEIC used to write all clear.
    static func grayWithAlpha(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A picture with black bars on its left and right.
    static func letterboxed(width: Int, height: Int, bar: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: bar, y: 0, width: width - 2 * bar, height: height))
        return context.makeImage()!
    }

    static func encode(_ image: CGImage, _ type: UTType, orientation: Int? = nil, quality: Double = 0.95) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let orientation { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PictureKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
