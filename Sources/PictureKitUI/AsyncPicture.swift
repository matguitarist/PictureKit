import SwiftUI

/// Shows a picture without blocking: decoded off the main thread at the size it's drawn, kept in a `PictureCache`,
/// with the placeholder until then. A picture already cached shows on the first frame. Replace a file at the same
/// path with `PictureCache.forget` and the view loads it again.
///
///     AsyncPicture(.file(coverURL), contentMode: .fill) {
///         Text(game.title.prefix(1))
///     }
///
/// With `.fill`, the picture is decoded just big enough to cover the view when cropped, so a wide picture in a
/// square tile stays sharp. `missing` shows when the picture can't be read, apart from the placeholder shown while
/// it loads.
public struct AsyncPicture<Placeholder: View, Missing: View>: View {
    private let source: PictureSource?
    private let contentMode: ContentMode
    private let alignment: Alignment
    private let maxPixels: Int?
    private let cache: PictureCache
    private let placeholder: Placeholder
    private let missing: Missing

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: Loaded?
    @State private var failed: Request?

    private struct Request: Hashable {
        var source: PictureSource
        var target: PictureTarget
        var revision: Int
    }

    private struct Loaded {
        var request: Request
        var image: CGImage
    }

    /// `maxPixels` fixes the decoded longest side; without it, the size comes from the view's size and the screen's
    /// scale. `alignment` places a picture that doesn't fill the view, such as a box on a shelf with `.bottom`.
    public init(_ source: PictureSource?, contentMode: ContentMode = .fit, alignment: Alignment = .center,
                maxPixels: Int? = nil, cache: PictureCache = .shared,
                @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder missing: () -> Missing) {
        self.source = source
        self.contentMode = contentMode
        self.alignment = alignment
        self.maxPixels = maxPixels
        self.cache = cache
        self.placeholder = placeholder()
        self.missing = missing()
    }

    public var body: some View {
        GeometryReader { proxy in
            let request = source.map { Request(source: $0, target: target(for: proxy.size), revision: PictureRevisions.shared.revision(of: $0.id)) }
            Group {
                if let request, let image = image(for: request) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
                        .clipped()
                } else if source == nil || (request != nil && failed == request) {
                    missing.frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    placeholder.frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .task(id: request) {
                guard let request, request.target.longSide > 0, image(for: request) == nil else { return }
                let image = await cache.image(request.source, request.target)
                guard !Task.isCancelled else { return }
                if let image { loaded = Loaded(request: request, image: image) } else { failed = request }
            }
        }
    }

    private func target(for size: CGSize) -> PictureTarget {
        if let maxPixels { return .longSide(maxPixels) }
        let (width, height) = (Int((size.width * displayScale).rounded(.up)), Int((size.height * displayScale).rounded(.up)))
        return contentMode == .fill ? .filling(width: width, height: height) : .longSide(max(width, height))
    }

    /// This view's own load for this request, else what the cache has: never the previous picture of a reused cell.
    private func image(for request: Request) -> CGImage? {
        if let loaded, loaded.request == request { return loaded.image }
        return cache.cached(request.source, request.target)
    }
}

extension AsyncPicture where Missing == Placeholder {
    /// The same view while loading and when there's no picture.
    public init(_ source: PictureSource?, contentMode: ContentMode = .fit, alignment: Alignment = .center,
                maxPixels: Int? = nil, cache: PictureCache = .shared, @ViewBuilder placeholder: () -> Placeholder) {
        let view = placeholder()
        self.init(source, contentMode: contentMode, alignment: alignment, maxPixels: maxPixels, cache: cache,
                  placeholder: { view }, missing: { view })
    }
}

extension AsyncPicture where Placeholder == Color, Missing == Color {
    /// With a plain gray placeholder.
    public init(_ source: PictureSource?, contentMode: ContentMode = .fit, alignment: Alignment = .center,
                maxPixels: Int? = nil, cache: PictureCache = .shared) {
        self.init(source, contentMode: contentMode, alignment: alignment, maxPixels: maxPixels, cache: cache) {
            Color.secondary.opacity(0.15)
        }
    }
}
