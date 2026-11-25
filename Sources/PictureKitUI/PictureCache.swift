import CoreGraphics
import Foundation
import Observation

/// Decoded pictures kept in memory up to a limit, decoded off the main thread at about the size they are drawn.
/// Sizes are rounded up to steps of 256 px, so a zoom slider doesn't make an entry for every width.
/// Safe from any thread: NSCache is thread-safe, only not marked Sendable.
public final class PictureCache: @unchecked Sendable {
    public static let shared = PictureCache()
    public static let sizeStep = 256

    private let cache = NSCache<NSString, CGImage>()

    /// `memoryLimit` in bytes of decoded pixels: 256 MB holds about 250 covers at 720 px.
    public init(memoryLimit: Int = 256 << 20) {
        cache.totalCostLimit = memoryLimit
    }

    public static func step(_ pixels: Int) -> Int {
        max(sizeStep, (pixels + sizeStep - 1) / sizeStep * sizeStep)
    }

    /// The picture when it's decoded already, at once: a cell scrolling back into view draws it on its first frame.
    public func cached(_ source: PictureSource, maxPixels: Int) -> CGImage? {
        cache.object(forKey: key(source.id, Self.step(maxPixels)))
    }

    /// The picture, decoded off the main thread when it isn't cached. Nil when it can't be read.
    public func image(_ source: PictureSource, maxPixels: Int, priority: TaskPriority = .userInitiated) async -> CGImage? {
        let size = Self.step(maxPixels)
        let key = key(source.id, size)
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: priority) { source.decode(size) }.value
        if let image { cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height) }
        return image
    }

    /// Forgets a picture at every size, for a file replaced at the same path, and tells the views showing it.
    public func forget(_ source: PictureSource) {
        for multiple in 1...32 { cache.removeObject(forKey: key(source.id, multiple * Self.sizeStep)) }
        let id = source.id
        Task { @MainActor in PictureRevisions.shared.bump(id) }
    }

    public func removeAll() { cache.removeAllObjects() }

    private func key(_ id: String, _ size: Int) -> NSString { "\(size)|\(id)" as NSString }
}

/// A number per picture that changes when it's replaced, so the views showing it load it again.
@MainActor @Observable
public final class PictureRevisions {
    public static let shared = PictureRevisions()
    private var revisions: [String: Int] = [:]

    public func revision(of id: String) -> Int { revisions[id] ?? 0 }
    public func bump(_ id: String) { revisions[id, default: 0] += 1 }
}
