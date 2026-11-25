import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PictureKitUI

@Test func aWidePictureFillingASquareIsDecodedByItsShortSide() throws {
    let png = Samples.encode(Samples.photo(width: 2500, height: 1000), .png)
    let image = try #require(Pictures.thumbnail(of: png, filling: 400, 400))
    #expect(image.height == 400 && image.width == 1000)
    // Never bigger than the picture itself.
    let small = try #require(Pictures.thumbnail(of: png, filling: 4000, 4000))
    #expect(small.width == 2500)
}

@Test func aSidewaysPictureFillsByItsUprightSize() throws {
    // Stored 400×300 with EXIF 6: shown 300 wide, 400 tall.
    let jpeg = Samples.encode(Samples.photo(width: 400, height: 300), .jpeg, orientation: 6)
    let image = try #require(Pictures.thumbnail(of: jpeg, filling: 150, 100))
    #expect(image.width == 150 && image.height == 200)
}

@Test func blankPicturesAreFound() {
    let clear = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    #expect(Pictures.isBlank(Samples.encode(clear.makeImage()!, .png)) == true)
    #expect(Pictures.isBlank(Samples.encode(Samples.photo(width: 32, height: 32), .png)) == false)
    #expect(Pictures.isBlank(Data("x".utf8)) == nil)
}

@Test func anAnimatedGIFStaysAsItIs() throws {
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, 2, nil)!
    CGImageDestinationAddImage(destination, Samples.flat(width: 64, height: 64, gray: 0.2), nil)
    CGImageDestinationAddImage(destination, Samples.flat(width: 64, height: 64, gray: 0.8), nil)
    CGImageDestinationFinalize(destination)
    let gif = output as Data
    #expect(Pictures.isAnimated(gif))
    let result = try Pictures.convert(gif, to: .photo)
    #expect(!result.converted && result.data == gif && result.fileExtension == "gif")
}

@Test func aDecodedCameraPictureIsStoredUpright() throws {
    let result = try Pictures.convert(Samples.photo(width: 2000, height: 1500), orientation: 6, to: .photo)
    #expect(result.converted && result.type == .heic && result.width == 1200 && result.height == 1600)
}

@Test func styleWithAnotherLongSide() {
    #expect(PictureStyle.photo.withLongSide(400).longSide == 400 && PictureStyle.photo.withLongSide(400).quality == 0.6)
}

@Test func aPDFWithTextIsNotRedrawnAsPictures() throws {
    let url = Samples.folder().appending(path: "schematic.pdf")
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPage(mediaBox: &box)
    context.draw(Samples.photo(width: 2400, height: 3100), in: box)
    // Text drawn with a font puts a Font in the page's resources.
    let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "U2 PMIC 1V8", attributes: [.init(kCTFontAttributeName as String): font]))
    context.textPosition = CGPoint(x: 72, y: 700)
    CTLineDraw(line, context)
    context.endPage()
    context.closePDF()
    #expect(ScannedPDF.hasText(url))
    #expect(!ScannedPDF.isWorthShrinking(url))
    #expect(ScannedPDF.isWorthShrinking(url, allowText: true))
}

@Test func aFileThatCannotBeReadIsMarkedToo() throws {
    let file = Samples.folder().appending(path: "broken.png")
    try Data("not really a png".utf8).write(to: file)
    #expect(PictureFile.isWorthCompressing(file, to: .artwork))
    #expect(PictureFile.compress(file, to: .artwork) == nil)
    #expect(!PictureFile.isWorthCompressing(file, to: .artwork))
}

@Test func storingAgainInTheSameFormatTrashesTheOldOneWhenAsked() throws {
    let base = Samples.folder().appending(path: "box")
    let png = Samples.encode(Samples.photo(width: 900, height: 900), .png)
    try PictureFile.store(png, at: base, style: .artwork, replaced: .delete)
    let second = try PictureFile.store(Samples.encode(Samples.photo(width: 600, height: 600), .png), at: base, style: .artwork, replaced: .delete)
    #expect(PictureFile.existing(base: base) == [second] && Pictures.info(at: second)?.width == 600)
}

@Test func forgettingAPictureForgetsWhatWasMadeFromIt() async throws {
    let file = Samples.folder().appending(path: "shot.png")
    try Samples.encode(Samples.letterboxed(width: 400, height: 200, bar: 40), .png).write(to: file)
    let cache = PictureCache()
    let plain = PictureSource.file(file)
    let trimmed = plain.applying("trimmed") { $0.trimmingDarkBorders() }
    await cache.prefetch([plain, trimmed], .longSide(400))
    #expect(cache.cached(plain, maxPixels: 400) != nil && cache.cached(trimmed, maxPixels: 400) != nil)
    cache.forget(plain)
    #expect(cache.cached(plain, maxPixels: 400) == nil && cache.cached(trimmed, maxPixels: 400) == nil)
}

@Test func fillingTargetsAreCachedApart() async throws {
    let file = Samples.folder().appending(path: "wide.png")
    try Samples.encode(Samples.photo(width: 2500, height: 1000), .png).write(to: file)
    let cache = PictureCache()
    let filled = try #require(await cache.image(.file(file), .filling(width: 300, height: 300)))
    #expect(filled.height == 512)
    #expect(cache.cached(.file(file), maxPixels: 300) == nil)
}
