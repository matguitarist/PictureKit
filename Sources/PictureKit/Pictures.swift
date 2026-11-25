import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PictureError: Error, Equatable, Sendable {
    /// Not a picture ImageIO can read, or one it couldn't write.
    case unreadable
    /// Bigger than `Pictures.largestFile` or `Pictures.largestPixels`: refused before it's decoded.
    case tooLarge
}

/// What a picture is, read from its header without decoding it.
public struct PictureInfo: Sendable, Hashable {
    public var width: Int
    public var height: Int
    /// "public.heic", "public.png"…
    public var type: UTType?
    /// EXIF orientation, 1 when upright.
    public var orientation: Int
    public var hasAlpha: Bool

    public var longSide: Int { max(width, height) }
    public var isUpright: Bool { orientation == 1 }
}

/// A picture after `Pictures.convert`.
public struct ConvertedPicture: Sendable, Equatable {
    public var data: Data
    public var width: Int
    public var height: Int
    public var type: UTType
    /// False when the original bytes were kept: already in the style, or smaller as they were.
    public var converted: Bool

    /// "heic", "png", "jpg"… for the file it's written to.
    public var fileExtension: String {
        if type.conforms(to: .jpeg) { return "jpg" }
        return type.preferredFilenameExtension ?? "png"
    }
}

/// Reads, converts and scales pictures with ImageIO, which never holds the full bitmap when it only needs a smaller one.
/// Every function here is safe to call from any thread; call them off the main thread for anything bigger than an icon.
public enum Pictures {
    /// Past this, a file is refused before it's read: no photo or artwork comes near it.
    public static let largestFile = 200 * 1024 * 1024
    /// 20,000 by 20,000. A bigger picture would take too much memory to scale.
    public static let largestPixels = 400_000_000

    // MARK: Reading

    public static func info(_ data: Data) -> PictureInfo? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary).flatMap(info)
    }

    public static func info(at url: URL) -> PictureInfo? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary).flatMap(info)
    }

    static func info(_ source: CGImageSource) -> PictureInfo? {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return PictureInfo(width: width, height: height,
                           type: CGImageSourceGetType(source).flatMap { UTType($0 as String) },
                           orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1,
                           hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false)
    }

    // MARK: Thumbnails

    /// The picture decoded at most `maxPixels` on its longest side, turned upright. Nil when it can't be read.
    public static func thumbnail(at url: URL, maxPixels: Int) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            .flatMap { thumbnail($0, maxPixels: maxPixels) }
    }

    public static func thumbnail(of data: Data, maxPixels: Int) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            .flatMap { thumbnail($0, maxPixels: maxPixels) }
    }

    public static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: Converting

    /// The picture in `style`: scaled down to its long side, turned upright, encoded in its format. The original bytes
    /// come back unchanged when they already match the style, or, with `onlyWhenSmaller`, when converting wouldn't
    /// make them smaller. Throws for data that isn't a picture, or one too big to decode safely.
    public static func convert(_ data: Data, to style: PictureStyle) throws -> ConvertedPicture {
        guard data.count <= largestFile else { throw PictureError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let info = info(source) else { throw PictureError.unreadable }
        guard info.width * info.height <= largestPixels else { throw PictureError.tooLarge }
        let fits = info.isUpright && style.longSide.map { info.longSide <= $0 } ?? true
        let original = ConvertedPicture(data: data, width: info.width, height: info.height,
                                        type: info.type ?? style.format.type, converted: false)
        if fits, isAlready(info, data: data, in: style) { return original }

        let side = min(style.longSide ?? info.longSide, info.longSide)
        guard let decoded = thumbnail(source, maxPixels: side), let image = inColor(decoded),
              let encoded = encode(image, as: style.format, quality: style.quality) else { throw PictureError.unreadable }
        if style.onlyWhenSmaller, fits, encoded.count >= data.count { return original }
        return ConvertedPicture(data: encoded, width: image.width, height: image.height, type: style.format.type, converted: true)
    }

    /// Already in the style's format, and, for a lossy one, light enough to have been compressed: it isn't done twice.
    private static func isAlready(_ info: PictureInfo, data: Data, in style: PictureStyle) -> Bool {
        guard info.type?.conforms(to: style.format.type) == true else { return false }
        guard style.format.isLossy else { return true }
        // A compressed photo is well under a byte a pixel; a HEIC saved at full quality isn't.
        return Double(data.count) <= Double(info.width * info.height) * 0.5
    }

    /// Encodes a decoded picture. Nil when ImageIO can't write it.
    public static func encode(_ image: CGImage, as format: PictureStyle.Format, quality: Double = 0.8) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, format.type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = format.isLossy ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// A grayscale picture redrawn in color: HEIC written from gray with transparency comes out all clear
    /// (Steam's Hollow Knight logo in Attic).
    static func inColor(_ image: CGImage) -> CGImage? {
        guard image.colorSpace?.model == .monochrome else { return image }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
