// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PictureKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Reading, converting, storing and shrinking pictures and scanned PDFs. No SwiftUI.
        .library(name: "PictureKit", targets: ["PictureKit"]),
        // The thumbnail cache and AsyncPicture, the view that shows a picture without blocking. Re-exports PictureKit.
        .library(name: "PictureKitUI", targets: ["PictureKitUI"]),
    ],
    targets: [
        .target(name: "PictureKit"),
        .target(name: "PictureKitUI", dependencies: ["PictureKit"]),
        .testTarget(name: "PictureKitTests", dependencies: ["PictureKit", "PictureKitUI"]),
    ]
)
