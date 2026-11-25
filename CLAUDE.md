# PictureKit

How my apps keep and show pictures: compressed to HEIC, scaled to the size they are used at, turned upright, decoded
off the main thread, cached with a memory limit. Shared by Attic, Thimble, BenchLog and RenChan, and the next ones.
A change here reaches every app at its next package update, so keep the API stable and additive.

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## Layout

- `Sources/PictureKit/` no SwiftUI, macOS and iOS:
  - `PictureStyle`: format, long side, quality, only-when-smaller; `.photo`, `.artwork`, `.cover`.
  - `Pictures`: `info`, `thumbnail`, `convert`, `encode`.
  - `PictureFile`: pictures as files named by what they belong to (`store`, `copy`, `find`, `compress`,
    `isWorthCompressing`, the "checked" mark).
  - `ScannedPDF`: shrinks heavy scanned PDFs.
  - `CGImage.trimmingDarkBorders()`.
- `Sources/PictureKitUI/` `PictureSource`, `PictureCache`, `PictureRevisions`, `AsyncPicture`. No strings: an
  app gives its own placeholder.
- `Tests/PictureKitTests/` Swift Testing. Samples are drawn in code; no fixture files.

## Rules

- Everything in PictureKit is safe from any thread and does no I/O on the main thread by itself; the UI target is
  where main-thread code lives.
- Never hold a full-size bitmap to make a smaller one: ImageIO thumbnails with `ShouldCache: false`.
- A file the person put somewhere goes to the Trash when replaced (`Disposal.trash`), never deleted.
- Add a test for every change. `swift build && swift test` pass, and the iOS build, then CI on macOS.
- Release: tag `x.y.z` and push the tag; apps use `from:`.

## Git

Commit after each working change, with a message that says what an app can now do.
