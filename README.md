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
.package(url: "https://github.com/matguitarist/PictureKit", from: "0.1.0"),
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
    from: 0.1.0
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

Make your own with `PictureStyle(format:longSide:quality:onlyWhenSmaller:)`. Every style turns pictures upright and
never compresses a picture twice: one already in the style comes back unchanged.

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

The size decoded is the view's longest side times the screen scale, in steps of 256 px. A picture already decoded
shows on the first frame. When a file is replaced at the same path, call `PictureCache.shared.forget(.file(url))`
and every view showing it loads it again.
