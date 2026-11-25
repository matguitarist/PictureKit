# PictureKit

How my apps keep and show pictures. It gathers what each app wrote on its own: Thimble's photos as small upright
HEIC, Attic's box art as HEIC only when that's smaller (with transparency kept, even from gray), Attic's thumbnail
cache and scanned-manual shrinking, RenChan's covers decoded off the main thread.

- **PictureKit**: read a picture's size and type without decoding it, make thumbnails, convert to HEIC, JPEG or PNG
  in a style, store pictures as files, shrink heavy scanned PDFs. No SwiftUI.
- **PictureKitUI**: `AsyncPicture`, a view that shows a picture without blocking, and `PictureCache`, decoded
  pictures kept up to a memory limit. Re-exports PictureKit.

macOS 14 or iOS 17 or later.

## Add it to an app

SwiftPM (`Package.swift`):

```swift
.package(url: "https://github.com/matguitarist/PictureKit", from: "0.2.0"),
// in the app target:
.product(name: "PictureKitUI", package: "PictureKit"),
// in a Kit target with no SwiftUI:
.product(name: "PictureKit", package: "PictureKit"),
```

XcodeGen (`project.yml`):

```yaml
packages:
  PictureKit:
    url: https://github.com/matguitarist/PictureKit
    from: 0.2.0
targets:
  App:
    dependencies:
      - package: PictureKit
        product: PictureKitUI
```

## Styles

| Style | For | Format | Long side | Quality | Original kept when smaller |
| --- | --- | --- | --- | --- | --- |
| `.photo` | photos, screenshots, pasted images | HEIC | 1600 px | 60% | no |
| `.artwork` | box art, logos, fan art | HEIC | full size | 80% | yes |
| `.cover` | a cover in a grid and an inspector | HEIC | 1200 px | 80% | yes |

Make your own with `PictureStyle(format:longSide:quality:onlyWhenSmaller:)`, or change one side:
`.artwork.withLongSide(1920)`, `.photo.withLongSide(400)` for a preview. Every style turns pictures upright and never
compresses a picture twice: one already in the style comes back unchanged. An animated GIF or PNG comes back unchanged
too (`Pictures.isAnimated`), since converting keeps one frame.

A picture already decoded, from the camera or the pasteboard: `Pictures.convert(cgImage, orientation: 6, to: .photo)`.

## Store a picture

```swift
import PictureKit

// A downloaded cover: Covers/<id>.heic, or .png when HEIC wouldn't be smaller. An older cover in another format goes.
let file = try PictureFile.store(data, at: coversFolder.appending(path: id.uuidString), style: .cover, replaced: .delete)

// Later, whatever its format:
let cover = PictureFile.find(base: coversFolder.appending(path: id.uuidString))

// Convert bytes without writing them:
let photo = try Pictures.convert(pasted, to: .photo)   // photo.data, photo.width, photo.fileExtension
```

Call these off the main thread for anything bigger than an icon.

## Shrink what's already there

```swift
for url in files where PictureFile.isWorthCompressing(url, to: .artwork, alsoChecked: ["com.attic.cover-checked"]) {
    PictureFile.compress(url, to: .artwork, original: .trash)   // box.png -> box.heic, or marked to skip next time
}
for pdf in manuals where ScannedPDF.isWorthShrinking(pdf) {
    ScannedPDF.shrink(pdf)                                       // pages redrawn at 150 dpi, kept only at 60% or less
}
```

A PDF with text in it (fonts on a page: a schematic, a datasheet, a scan with a searchable text layer) is never worth
shrinking unless you pass `allowText: true`: redrawn as pictures, its text couldn't be searched. A file that can't be
read or didn't get smaller is marked, so it isn't tried again.

After a file is replaced, `URL.resourceValues` on a URL you held may still give the old size: read it from a fresh
`URL` or `FileManager.attributesOfItem`.

Other checks: `Pictures.isBlank(data)` (every pixel clear), `Pictures.info(data)` (size, type, orientation, alpha,
without decoding).

## Show a picture

```swift
import PictureKitUI

AsyncPicture(.file(coverURL), contentMode: .fill) {
    Text(game.title.prefix(1))            // shown until the picture is decoded, and when there is none
}
.frame(width: 180, height: 270)

// A picture inside an archive, read only when shown:
AsyncPicture(.data(id: "\(archive.path)#\(path)") { try picture.data() }, maxPixels: 400)

// With black bars trimmed, cached apart:
AsyncPicture(.file(screenshot).applying("trimmed") { $0.trimmingDarkBorders() }, contentMode: .fill)
```

The size decoded comes from the view's size times the screen scale, in steps of 256 px. With `.fill`, the picture
is decoded just big enough to cover the view once cropped, so a wide picture in a square tile stays sharp. A picture
already decoded shows on the first frame.

```swift
// Placed at the bottom, like a box on a shelf; a different view when there's no picture.
AsyncPicture(.file(box), alignment: .bottom) {
    ProgressView()
} missing: {
    Image(systemName: "photo")
}

// Before a snapshot, or the first screen of a grid:
await PictureCache.shared.prefetch(sources, .longSide(512))
```

When a file is replaced at the same path, call `PictureCache.shared.forget(.file(url))`: it forgets every size and
every picture made from it with `applying`, and every view showing them loads them again.

## Testing pictures in an app

Draw samples in code rather than keeping fixture files. To make a photo "taken sideways", pass the orientation as a
typed `[CFString: Any]` (`[kCGImagePropertyOrientation: 6]`) to `CGImageDestinationAddImage`: a plain dictionary
literal cast to `CFDictionary` can drop it silently.
