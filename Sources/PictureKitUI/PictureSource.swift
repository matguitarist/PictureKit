import CoreGraphics
import Foundation
@_exported import PictureKit

/// The size a picture is decoded at.
public enum PictureTarget: Sendable, Hashable {
    /// At most this many pixels on its longest side, for a picture drawn whole (`.fit`).
    case longSide(Int)
    /// Just big enough to cover this many pixels when cropped, for a picture drawn with `.fill`.
    case filling(width: Int, height: Int)

    /// Rounded up to steps of `PictureCache.sizeStep`, so close sizes share a cache entry.
    public var stepped: PictureTarget {
        switch self {
        case .longSide(let side): .longSide(PictureCache.step(side))
        case .filling(let width, let height): .filling(width: PictureCache.step(width), height: PictureCache.step(height))
        }
    }

    /// The longest side, for a source that only knows that.
    public var longSide: Int {
        switch self {
        case .longSide(let side): side
        case .filling(let width, let height): max(width, height)
        }
    }

    var key: String {
        switch self {
        case .longSide(let side): "\(side)"
        case .filling(let width, let height): "\(width)x\(height)"
        }
    }
}

/// Where a picture comes from, for the cache and `AsyncPicture`: a file, bytes read on demand (a picture inside an
/// archive), or either with a change applied once decoded. Two sources with the same id are the same picture.
public struct PictureSource: Sendable, Hashable {
    public let id: String
    /// The id of the picture this one was made from with `applying`; its own id otherwise.
    public let baseID: String
    let decode: @Sendable (PictureTarget) -> CGImage?

    /// A source that decodes at a longest side; a `.filling` target asks it for the longest side of the area.
    public init(id: String, decode: @escaping @Sendable (_ maxPixels: Int) -> CGImage?) {
        self.init(id: id, baseID: id, target: { decode($0.longSide) })
    }

    /// A source that handles both targets itself, such as with `Pictures.thumbnail(_:filling:_:)`.
    public init(id: String, decodeTarget: @escaping @Sendable (PictureTarget) -> CGImage?) {
        self.init(id: id, baseID: id, target: decodeTarget)
    }

    init(id: String, baseID: String, target: @escaping @Sendable (PictureTarget) -> CGImage?) {
        self.id = id
        self.baseID = baseID
        self.decode = target
    }

    /// A picture file.
    public static func file(_ url: URL) -> PictureSource {
        PictureSource(id: url.standardizedFileURL.path) { target in
            switch target {
            case .longSide(let side): Pictures.thumbnail(at: url, maxPixels: side)
            case .filling(let width, let height): Pictures.thumbnail(at: url, filling: width, height)
            }
        }
    }

    /// Bytes read only when the picture is decoded, off the main thread. `id` must name them uniquely.
    public static func data(id: String, _ read: @escaping @Sendable () throws -> Data) -> PictureSource {
        PictureSource(id: id) { target in
            guard let data = try? read() else { return nil }
            switch target {
            case .longSide(let side): return Pictures.thumbnail(of: data, maxPixels: side)
            case .filling(let width, let height): return Pictures.thumbnail(of: data, filling: width, height)
            }
        }
    }

    /// The same picture with a change applied after decoding, such as `{ $0.trimmingDarkBorders() }`, cached apart
    /// under `name`. `PictureCache.forget` on either forgets both.
    public func applying(_ name: String, _ change: @escaping @Sendable (CGImage) -> CGImage) -> PictureSource {
        let decode = self.decode
        return PictureSource(id: "\(id)#\(name)", baseID: baseID) { decode($0).map(change) }
    }

    public static func == (a: PictureSource, b: PictureSource) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
