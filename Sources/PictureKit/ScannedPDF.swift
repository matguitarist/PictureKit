import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks heavy scanned PDFs (game manuals, invoices, schematics) by redrawing each page as a JPEG, which keeps
/// scanned text sharp at full screen. Text PDFs are left alone: they are light already.
public enum ScannedPDF {
    /// Written as the PDF's Creator, so a file is never redone.
    public static let creator = "PictureKit"
    /// Set on a PDF that didn't get smaller, for the same reason.
    public static let checkedAttribute = "com.matguitarist.picturekit.pdf-checked"
    /// Scans heavier than this per page are worth redoing: a cartridge-era manual is 50–80 KB a page.
    public static let heavyBytesPerPage = 150_000

    /// Whether a PDF is a heavy scan not tried yet. A PDF with text in it (fonts on any page: a schematic, a datasheet,
    /// a scan with a searchable text layer) isn't, since redrawing it as pictures would lose that text; pass
    /// `allowText` to shrink those too. `alsoChecked` and `alsoCreators` take an app's own older marks.
    public static func isWorthShrinking(_ url: URL, allowText: Bool = false, alsoChecked: [String] = [], alsoCreators: [String] = []) -> Bool {
        guard url.pathExtension.lowercased() == "pdf",
              !([checkedAttribute] + alsoChecked).contains(where: { PictureFile.hasAttribute($0, url) }),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0,
              !([creator] + alsoCreators).contains(Self.creator(of: document) ?? ""),
              size / document.numberOfPages > heavyBytesPerPage else { return false }
        return allowText || !hasText(document)
    }

    /// Whether any page uses a font, the sign of text a reader can select and search.
    public static func hasText(_ url: URL) -> Bool {
        CGPDFDocument(url as CFURL).map(hasText) ?? false
    }

    static func hasText(_ document: CGPDFDocument) -> Bool {
        guard document.numberOfPages > 0 else { return false }
        for number in 1...document.numberOfPages {
            guard let dictionary = document.page(at: number)?.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            var fonts: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
               CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts, CGPDFDictionaryGetCount(fonts) > 0 {
                return true
            }
        }
        return false
    }

    /// Redraws each page at `dpi` as a JPEG. The new file replaces the old one (which goes per `original`) only when
    /// it's at most `keepBelow` of its size; otherwise the PDF is marked as tried. Returns whether it was replaced.
    @discardableResult
    public static func shrink(_ url: URL, dpi: Double = 150, quality: Double = 0.7, keepBelow: Double = 0.6,
                              original: Disposal = .trash) -> Bool {
        let fileManager = FileManager.default
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0,
              let before = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return false }
        let temporary = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).pdf")
        defer { try? fileManager.removeItem(at: temporary) }
        guard redraw(document, to: temporary, dpi: dpi, quality: quality),
              let after = (try? temporary.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              Double(after) <= Double(before) * keepBelow else {
            PictureFile.mark(url, attribute: checkedAttribute)
            return false
        }
        if original == .keep {
            let kept = url.deletingPathExtension().appendingPathExtension("original.pdf")
            guard (try? fileManager.moveItem(at: url, to: kept)) != nil else { return false }
        } else {
            original.apply(to: url)
            guard !fileManager.fileExists(atPath: url.path) else { return false }
        }
        return (try? fileManager.moveItem(at: temporary, to: url)) != nil
    }

    static func redraw(_ document: CGPDFDocument, to destination: URL, dpi: Double, quality: Double) -> Bool {
        let info = [kCGPDFContextCreator: creator] as CFDictionary
        guard let output = CGContext(destination as CFURL, mediaBox: nil, info),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let scale = dpi / 72
        for number in 1...document.numberOfPages {
            // Turned pages would need their rotation redone; leave those be.
            guard let page = document.page(at: number), page.rotationAngle == 0 else { return false }
            let box = page.getBoxRect(.mediaBox)
            let (width, height) = (Int(box.width * scale), Int(box.height * scale))
            guard width > 0, height > 0,
                  let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.scaleBy(x: scale, y: scale)
            bitmap.translateBy(x: -box.minX, y: -box.minY)
            bitmap.drawPDFPage(page)
            guard let rendered = bitmap.makeImage(),
                  let jpeg = Pictures.encode(rendered, as: .jpeg, quality: quality),
                  let provider = CGDataProvider(data: jpeg as CFData),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return false }
            var pageBox = CGRect(origin: .zero, size: box.size)
            output.beginPage(mediaBox: &pageBox)
            output.draw(image, in: pageBox)
            output.endPage()
        }
        output.closePDF()
        return true
    }

    static func creator(of document: CGPDFDocument) -> String? {
        var value: CGPDFStringRef?
        guard let info = document.info, CGPDFDictionaryGetString(info, "Creator", &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }
}
