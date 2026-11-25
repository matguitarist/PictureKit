import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PictureKit

@Test func infoReadsTheHeaderOnly() throws {
    let png = Samples.encode(Samples.photo(width: 300, height: 200), .png)
    let info = try #require(Pictures.info(png))
    #expect(info.width == 300 && info.height == 200 && info.type == .png && info.isUpright && !info.hasAlpha)
    #expect(Pictures.info(Data("not a picture".utf8)) == nil)
}

@Test func aPhotoBecomesASmallUprightHEIC() throws {
    let png = Samples.encode(Samples.photo(width: 3000, height: 2000), .png)
    let result = try Pictures.convert(png, to: .photo)
    #expect(result.converted && result.type == .heic && result.fileExtension == "heic")
    #expect(result.width == 1600 && result.height == 1067)
    #expect(result.data.count < png.count / 10)
    #expect(Pictures.info(result.data)?.type == .heic)
}

@Test func aPhotoIsNeverCompressedTwice() throws {
    let png = Samples.encode(Samples.photo(width: 2000, height: 1000), .png)
    let once = try Pictures.convert(png, to: .photo)
    let twice = try Pictures.convert(once.data, to: .photo)
    #expect(!twice.converted && twice.data == once.data)
}

@Test func aSidewaysPhotoIsTurnedUpright() throws {
    // EXIF 6: the camera was turned; the stored pixels are 400 wide, shown 400 tall.
    let jpeg = Samples.encode(Samples.photo(width: 400, height: 300), .jpeg, orientation: 6)
    #expect(Pictures.info(jpeg)?.orientation == 6)
    let result = try Pictures.convert(jpeg, to: .photo)
    #expect(result.converted && result.width == 300 && result.height == 400)
    #expect(Pictures.info(result.data)?.isUpright == true)
}

@Test func artworkStaysAsItIsWhenHEICIsNotSmaller() throws {
    let tiny = Samples.encode(Samples.flat(width: 16, height: 16), .png)
    let result = try Pictures.convert(tiny, to: .artwork)
    #expect(!result.converted && result.data == tiny && result.fileExtension == "png")
}

@Test func artworkShrinksABigPNGAndKeepsItsSize() throws {
    let png = Samples.encode(Samples.photo(width: 1200, height: 1600), .png)
    let result = try Pictures.convert(png, to: .artwork)
    #expect(result.converted && result.width == 1200 && result.height == 1600 && result.data.count < png.count)
}

@Test func aCoverIsCappedEvenWhenTheOriginalIsSmallerInBytes() throws {
    // A big flat PNG is tiny in bytes, but too many pixels for a cover: it's scaled down anyway.
    let png = Samples.encode(Samples.flat(width: 3000, height: 4000), .png)
    let result = try Pictures.convert(png, to: .cover)
    #expect(result.converted && max(result.width, result.height) == 1200)
}

@Test func transparencyIsKeptEvenFromGray() throws {
    let png = Samples.encode(Samples.grayWithAlpha(width: 600, height: 600), .png)
    let result = try Pictures.convert(png, to: PictureStyle(format: .heic, onlyWhenSmaller: false))
    #expect(result.converted && Pictures.info(result.data)?.hasAlpha == true)
    // The middle is opaque, not cleared.
    let image = try #require(Pictures.thumbnail(of: result.data, maxPixels: 600))
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -300, y: -300, width: 600, height: 600))
    let alpha = context.data!.bindMemory(to: UInt8.self, capacity: 4)[3]
    #expect(alpha > 200)
}

@Test func whatIsNotAPictureIsRefused() {
    #expect(throws: PictureError.unreadable) { try Pictures.convert(Data("<html>expired link</html>".utf8), to: .photo) }
}

@Test func thumbnailsFitTheSizeAsked() throws {
    let png = Samples.encode(Samples.photo(width: 2000, height: 1000), .png)
    let image = try #require(Pictures.thumbnail(of: png, maxPixels: 500))
    #expect(image.width == 500 && image.height == 250)
}

@Test func darkBordersAreTrimmed() {
    let image = Samples.letterboxed(width: 400, height: 200, bar: 40).trimmingDarkBorders()
    #expect(image.width == 320 && image.height == 200)
    let plain = Samples.flat(width: 100, height: 100, gray: 0.6)
    #expect(plain.trimmingDarkBorders().width == 100)
}
