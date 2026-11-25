import SwiftUI

/// Shows a picture without blocking: decoded off the main thread at the size it's drawn, kept in a `PictureCache`,
/// with the placeholder until then. A picture already cached shows on the first frame. Replace a file at the same
/// path with `PictureCache.forget` and the view loads it again.
///
///     AsyncPicture(.file(coverURL), contentMode: .fill) {
///         Text(game.title.prefix(1))
///     }
public struct AsyncPicture<Placeholder: View>: View {
    private let source: PictureSource?
    private let contentMode: ContentMode
    private let maxPixels: Int?
    private let cache: PictureCache
    private let placeholder: Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: Loaded?

    private struct Request: Hashable {
        var source: PictureSource
        var pixels: Int
        var revision: Int
    }

    private struct Loaded {
        var request: Request
        var image: CGImage
    }

    /// `maxPixels` fixes the decoded size; without it, the view's longest side times the screen's scale.
    public init(_ source: PictureSource?, contentMode: ContentMode = .fit, maxPixels: Int? = nil,
                cache: PictureCache = .shared, @ViewBuilder placeholder: () -> Placeholder) {
        self.source = source
        self.contentMode = contentMode
        self.maxPixels = maxPixels
        self.cache = cache
        self.placeholder = placeholder()
    }

    public var body: some View {
        GeometryReader { proxy in
            let request = source.map {
                Request(source: $0,
                        pixels: PictureCache.step(maxPixels ?? Int((max(proxy.size.width, proxy.size.height) * displayScale).rounded(.up))),
                        revision: PictureRevisions.shared.revision(of: $0.id))
            }
            Group {
                if let request, let image = image(for: request) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    placeholder
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .task(id: request) {
                guard let request, request.pixels > 0, image(for: request) == nil else { return }
                if let image = await cache.image(request.source, maxPixels: request.pixels), !Task.isCancelled {
                    loaded = Loaded(request: request, image: image)
                }
            }
        }
    }

    /// This view's own load for this request, else what the cache has: never the previous picture of a reused cell.
    private func image(for request: Request) -> CGImage? {
        if let loaded, loaded.request == request { return loaded.image }
        return cache.cached(request.source, maxPixels: request.pixels)
    }
}

extension AsyncPicture where Placeholder == Color {
    /// With a plain gray placeholder.
    public init(_ source: PictureSource?, contentMode: ContentMode = .fit, maxPixels: Int? = nil, cache: PictureCache = .shared) {
        self.init(source, contentMode: contentMode, maxPixels: maxPixels, cache: cache) { Color.secondary.opacity(0.15) }
    }
}
