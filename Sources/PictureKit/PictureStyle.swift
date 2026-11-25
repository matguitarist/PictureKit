import Foundation
import UniformTypeIdentifiers

/// How a picture is kept: its format, its longest side, its quality, and whether a smaller original stays as it is.
public struct PictureStyle: Sendable, Hashable {
    public enum Format: String, Sendable, Hashable, CaseIterable {
        case heic, jpeg, png

        public var type: UTType {
            switch self {
            case .heic: .heic
            case .jpeg: .jpeg
            case .png: .png
            }
        }

        public var fileExtension: String {
            switch self {
            case .heic: "heic"
            case .jpeg: "jpg"
            case .png: "png"
            }
        }

        var isLossy: Bool { self != .png }
    }

    public var format: Format
    /// The longest side in pixels; a bigger picture is scaled down to it. Nil keeps the picture's size.
    public var longSide: Int?
    /// 0 to 1, for HEIC and JPEG.
    public var quality: Double
    /// Keeps the original bytes when converting wouldn't make them smaller, as long as the original is upright and
    /// fits `longSide`: a small palette PNG stays a PNG.
    public var onlyWhenSmaller: Bool

    public init(format: Format = .heic, longSide: Int? = nil, quality: Double = 0.8, onlyWhenSmaller: Bool = true) {
        self.format = format
        self.longSide = longSide
        self.quality = quality
        self.onlyWhenSmaller = onlyWhenSmaller
    }

    /// The same style with another longest side: `.artwork.withLongSide(1920)`, `.photo.withLongSide(400)` for a preview.
    public func withLongSide(_ side: Int?) -> PictureStyle {
        var style = self
        style.longSide = side
        return style
    }

    /// Photos and screenshots people add (Thimble's pictures, BenchLog's repair photos): HEIC at 60%, at most
    /// 1600 px, turned upright. Readable on screen and by a model, a few hundred KB at most.
    public static let photo = PictureStyle(format: .heic, longSide: 1600, quality: 0.6, onlyWhenSmaller: false)

    /// Box art, covers, logos and fan art (Attic's media): HEIC at 80% at full size, only when that's smaller.
    /// About 40% smaller than PNG at no visible cost, with transparency kept.
    public static let artwork = PictureStyle(format: .heic, longSide: nil, quality: 0.8, onlyWhenSmaller: true)

    /// A cover shown in a grid and an inspector (RenChan's covers): artwork, at most 1200 px.
    public static let cover = PictureStyle(format: .heic, longSide: 1200, quality: 0.8, onlyWhenSmaller: true)
}
