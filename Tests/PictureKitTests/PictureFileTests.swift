import Foundation
import Testing
@testable import PictureKit

@Test func storingReplacesAnOlderFormat() throws {
    let folder = Samples.folder()
    let base = folder.appending(path: "covers/game-1")
    let png = Samples.encode(Samples.photo(width: 800, height: 1200), .png)
    let first = try PictureFile.store(png, at: base, style: nil, replaced: .delete)
    #expect(first.lastPathComponent == "game-1.png")
    let second = try PictureFile.store(png, at: base, style: .cover, replaced: .delete)
    #expect(second.lastPathComponent == "game-1.heic")
    #expect(PictureFile.existing(base: base) == [second] && PictureFile.find(base: base) == second)
}

@Test func storingSomethingThatIsNotAPictureWritesNothing() {
    let base = Samples.folder().appending(path: "cover")
    #expect(throws: PictureError.unreadable) { try PictureFile.store(Data("nope".utf8), at: base, style: .cover) }
    #expect(PictureFile.existing(base: base).isEmpty)
}

@Test func compressingRewritesBesideAndMarksWhatDidNotShrink() throws {
    let folder = Samples.folder()
    let big = folder.appending(path: "box.png")
    try Samples.encode(Samples.photo(width: 900, height: 900), .png).write(to: big)
    #expect(PictureFile.isWorthCompressing(big, to: .artwork))
    let heic = try #require(PictureFile.compress(big, to: .artwork, original: .delete))
    #expect(heic.lastPathComponent == "box.heic" && !FileManager.default.fileExists(atPath: big.path))
    #expect(!PictureFile.isWorthCompressing(heic, to: .artwork))

    let tiny = folder.appending(path: "dot.png")
    try Samples.encode(Samples.flat(width: 8, height: 8), .png).write(to: tiny)
    #expect(PictureFile.compress(tiny, to: .artwork, original: .delete) == nil)
    #expect(FileManager.default.fileExists(atPath: tiny.path) && !PictureFile.isWorthCompressing(tiny, to: .artwork))
}

@Test func anAppsOwnOlderMarkIsHonored() throws {
    let file = Samples.folder().appending(path: "logo.png")
    try Samples.encode(Samples.photo(width: 200, height: 200), .png).write(to: file)
    PictureFile.mark(file, attribute: "com.attic.cover-checked")
    #expect(PictureFile.isWorthCompressing(file, to: .artwork))
    #expect(!PictureFile.isWorthCompressing(file, to: .artwork, alsoChecked: ["com.attic.cover-checked"]))
}

@Test func copyingAVideoKeepsItAsItIs() throws {
    let folder = Samples.folder()
    let video = folder.appending(path: "clip.mp4")
    try Data(repeating: 7, count: 64).write(to: video)
    let copy = try PictureFile.copy(video, to: folder.appending(path: "media/game"), style: .artwork)
    let copied = try Data(contentsOf: copy)
    #expect(copy.lastPathComponent == "game.mp4" && copied == Data(repeating: 7, count: 64))
}
