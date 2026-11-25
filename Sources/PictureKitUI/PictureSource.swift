import CoreGraphics
import Foundation
@_exported import PictureKit

/// Where a picture comes from, for the cache and `AsyncPicture`: a file, bytes read on demand (a picture inside an
/// archive), or either with a change applied once decoded. Two sources with the same id are the same picture.
public struct PictureSource: Sendable, Hashable {
    public let id: String
    let decode: @Sendable (_ maxPixels: Int) -> CGImage?

    public init(id: String, decode: @escaping @Sendable (_ maxPixels: Int) -> CGImage?) {
        self.id = id
        self.decode = decode
    }

    /// A picture file.
    public static func file(_ url: URL) -> PictureSource {
        PictureSource(id: url.standardizedFileURL.path) { Pictures.thumbnail(at: url, maxPixels: $0) }
    }

    /// Bytes read only when the picture is decoded, off the main thread. `id` must name them uniquely.
    public static func data(id: String, _ read: @escaping @Sendable () throws -> Data) -> PictureSource {
        PictureSource(id: id) { pixels in (try? read()).flatMap { Pictures.thumbnail(of: $0, maxPixels: pixels) } }
    }

    /// The same picture with a change applied after decoding, such as `{ $0.trimmingDarkBorders() }`, cached apart
    /// under `name`.
    public func applying(_ name: String, _ change: @escaping @Sendable (CGImage) -> CGImage) -> PictureSource {
        let decode = self.decode
        return PictureSource(id: "\(id)#\(name)") { decode($0).map(change) }
    }

    public static func == (a: PictureSource, b: PictureSource) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
