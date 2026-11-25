import CoreGraphics
import Foundation
import Testing
@testable import PictureKit

/// A one-page PDF with a scan drawn in at full resolution, as a scanner writes it.
private func scannedPDF(_ url: URL, pixels: Int) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPage(mediaBox: &box)
    context.draw(Samples.photo(width: pixels, height: pixels * 792 / 612), in: box)
    context.endPage()
    context.closePDF()
}

@Test func aHeavyScanIsShrunkOnceAndALightOneIsLeftAlone() throws {
    let folder = Samples.folder()
    let heavy = folder.appending(path: "manual.pdf")
    scannedPDF(heavy, pixels: 2400)
    #expect(ScannedPDF.isWorthShrinking(heavy))
    #expect(ScannedPDF.shrink(heavy, original: .delete))
    #expect(!ScannedPDF.isWorthShrinking(heavy))
    #expect(CGPDFDocument(heavy as CFURL)?.numberOfPages == 1)

    let light = folder.appending(path: "note.pdf")
    scannedPDF(light, pixels: 120)
    #expect(!ScannedPDF.isWorthShrinking(light))
}
