import CoreGraphics
import Foundation
import Observation

/// Decoded pictures kept in memory up to a limit, decoded off the main thread at about the size they are drawn.
/// Sizes are rounded up to steps of 256 px, so a zoom slider doesn't make an entry for every width.
/// Safe from any thread.
public final class PictureCache: @unchecked Sendable {
    public static let shared = PictureCache()
    public static let sizeStep = 256

    private let cache = NSCache<NSString, CGImage>()
    private let lock = NSLock()
    /// Every cache key made for a picture, by its base id, so forget can reach them all: NSCache can't list its keys.
    private var keys: [String: Set<String>] = [:]

    /// `memoryLimit` in bytes of decoded pixels: 256 MB holds about 250 covers at 720 px.
    public init(memoryLimit: Int = 256 << 20) {
        cache.totalCostLimit = memoryLimit
    }

    public static func step(_ pixels: Int) -> Int {
        max(sizeStep, (pixels + sizeStep - 1) / sizeStep * sizeStep)
    }

    /// The picture when it's decoded already, at once: a cell scrolling back into view draws it on its first frame.
    public func cached(_ source: PictureSource, _ target: PictureTarget) -> CGImage? {
        cache.object(forKey: key(source.id, target.stepped))
    }

    public func cached(_ source: PictureSource, maxPixels: Int) -> CGImage? { cached(source, .longSide(maxPixels)) }

    /// The picture, decoded off the main thread when it isn't cached. Nil when it can't be read.
    public func image(_ source: PictureSource, _ target: PictureTarget, priority: TaskPriority = .userInitiated) async -> CGImage? {
        let target = target.stepped
        let key = key(source.id, target)
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: priority) { source.decode(target) }.value
        if let image {
            cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
            lock.withLock { _ = keys[source.baseID, default: []].insert(key as String) }
        }
        return image
    }

    public func image(_ source: PictureSource, maxPixels: Int, priority: TaskPriority = .userInitiated) async -> CGImage? {
        await image(source, .longSide(maxPixels), priority: priority)
    }

    /// Decodes pictures ahead of time, such as the first screen of a grid before a snapshot.
    public func prefetch(_ sources: [PictureSource], _ target: PictureTarget) async {
        await withTaskGroup(of: Void.self) { group in
            for source in sources { group.addTask { _ = await self.image(source, target, priority: .utility) } }
        }
    }

    /// Forgets a picture at every size, and every picture made from it with `applying`, for a file replaced at the
    /// same path; the views showing them load them again.
    public func forget(_ source: PictureSource) {
        let gone = lock.withLock { keys.removeValue(forKey: source.baseID) ?? [] }
        for key in gone { cache.removeObject(forKey: key as NSString) }
        let ids = Set([source.id, source.baseID] + gone.compactMap { $0.split(separator: "|", maxSplits: 1).last.map(String.init) })
        Task { @MainActor in ids.forEach(PictureRevisions.shared.bump) }
    }

    public func removeAll() {
        cache.removeAllObjects()
        lock.withLock { keys.removeAll() }
    }

    private func key(_ id: String, _ target: PictureTarget) -> NSString { "\(target.key)|\(id)" as NSString }
}

/// A number per picture that changes when it's replaced, so the views showing it load it again.
@MainActor @Observable
public final class PictureRevisions {
    public static let shared = PictureRevisions()
    private var revisions: [String: Int] = [:]

    public func revision(of id: String) -> Int { revisions[id] ?? 0 }
    public func bump(_ id: String) { revisions[id, default: 0] += 1 }
}
