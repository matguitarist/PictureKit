import CoreGraphics
import Foundation
import Testing
@testable import PictureKitUI

@Test func theCacheDecodesOnceAtAStepAndForgets() async throws {
    let file = Samples.folder().appending(path: "cover.png")
    try Samples.encode(Samples.photo(width: 1000, height: 1500), .png).write(to: file)
    let cache = PictureCache(memoryLimit: 64 << 20)
    let source = PictureSource.file(file)
    #expect(cache.cached(source, maxPixels: 300) == nil)
    let image = try #require(await cache.image(source, maxPixels: 300))
    #expect(max(image.width, image.height) == 512)
    #expect(cache.cached(source, maxPixels: 400) != nil)
    cache.forget(source)
    #expect(cache.cached(source, maxPixels: 300) == nil)
}

@Test func sourcesAreTheSameByIdAndChangesAreCachedApart() async throws {
    let png = Samples.encode(Samples.letterboxed(width: 400, height: 200, bar: 40), .png)
    let source = PictureSource.data(id: "archive.rpa#cg/a.png") { png }
    #expect(source == PictureSource.data(id: "archive.rpa#cg/a.png") { Data() })
    let trimmed = source.applying("trimmed") { $0.trimmingDarkBorders() }
    #expect(trimmed != source)
    let cache = PictureCache()
    let whole = try #require(await cache.image(source, maxPixels: 400))
    let cut = try #require(await cache.image(trimmed, maxPixels: 400))
    #expect(whole.width == 400 && cut.width == 320)
}

@Test func sizesStepBy256() {
    #expect(PictureCache.step(1) == 256 && PictureCache.step(256) == 256 && PictureCache.step(257) == 512)
}
