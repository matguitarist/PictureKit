import Foundation

/// What happens to a file a new one replaces.
public enum Disposal: Sendable, Hashable {
    /// To the Trash, where the person can get it back. The default for anything the person put there.
    case trash
    /// Deleted: caches, and files only the app ever made.
    case delete
    /// Left where it is.
    case keep

    func apply(to url: URL) {
        switch self {
        case .trash: try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        case .delete: try? FileManager.default.removeItem(at: url)
        case .keep: break
        }
    }
}

/// Pictures kept as files named by what they belong to, whatever their format: `Covers/<id>` is `<id>.heic` today and
/// may be `<id>.png` from an older version.
public enum PictureFile {
    /// Most compact first, the order a picture is looked for in.
    public static let imageExtensions = ["heic", "webp", "avif", "png", "jpg", "jpeg", "gif", "tiff", "bmp"]

    /// Set on a file converting didn't make smaller, so it isn't tried again.
    public static let checkedAttribute = "com.matguitarist.picturekit.checked"

    /// The files already there for `base`, in any picture format, most compact first.
    public static func existing(base: URL, extensions: [String] = imageExtensions) -> [URL] {
        extensions.map { base.appendingPathExtension($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The first picture there for `base`.
    public static func find(base: URL) -> URL? { existing(base: base).first }

    /// Writes `data` as `base` plus the extension its format takes, converted to `style` (nil writes it as it is).
    /// An earlier picture at `base` in another format goes per `replaced`. The folder is made when missing. Throws when
    /// `data` isn't a picture: nothing is written then.
    @discardableResult
    public static func store(_ data: Data, at base: URL, style: PictureStyle?, replaced: Disposal = .trash) throws -> URL {
        let picture: ConvertedPicture
        if let style {
            picture = try Pictures.convert(data, to: style)
        } else {
            guard let info = Pictures.info(data) else { throw PictureError.unreadable }
            picture = ConvertedPicture(data: data, width: info.width, height: info.height, type: info.type ?? .png, converted: false)
        }
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = base.appendingPathExtension(picture.fileExtension)
        try picture.data.write(to: destination, options: .atomic)
        for old in existing(base: base) where old.pathExtension != destination.pathExtension { replaced.apply(to: old) }
        return destination
    }

    /// Copies the picture at `url` to `base`, converted to `style`. A file that isn't a picture (a video, a PDF) is
    /// copied as it is, with its own extension.
    @discardableResult
    public static func copy(_ url: URL, to base: URL, style: PictureStyle?, replaced: Disposal = .trash) throws -> URL {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if Pictures.info(data) != nil { return try store(data, at: base, style: style, replaced: replaced) }
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = base.appendingPathExtension(url.pathExtension.lowercased())
        if FileManager.default.fileExists(atPath: destination.path) { replaced.apply(to: destination) }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// Whether a picture file is worth converting to `style`: not in its format yet, and not tried before (by
    /// PictureKit, or by an app's own older attribute in `alsoChecked`).
    public static func isWorthCompressing(_ url: URL, to style: PictureStyle, alsoChecked: [String] = []) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard imageExtensions.contains(ext), ext != style.format.fileExtension, !(style.format == .jpeg && ext == "jpeg") else { return false }
        if ([checkedAttribute] + alsoChecked).contains(where: { hasAttribute($0, url) }) { return false }
        // One beside it already has the name it would take.
        return !FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension(style.format.fileExtension).path)
    }

    /// Rewrites a picture file in `style` beside it, then disposes of the original. Returns the new file, or nil when
    /// it was left as it was; a file converting doesn't make smaller is marked so it isn't tried again.
    @discardableResult
    public static func compress(_ url: URL, to style: PictureStyle, original: Disposal = .trash) -> URL? {
        guard let data = try? Data(contentsOf: url), let picture = try? Pictures.convert(data, to: style) else { return nil }
        guard picture.converted else {
            mark(url)
            return nil
        }
        let destination = url.deletingPathExtension().appendingPathExtension(picture.fileExtension)
        guard destination != url, !FileManager.default.fileExists(atPath: destination.path),
              (try? picture.data.write(to: destination, options: .atomic)) != nil else { return nil }
        original.apply(to: url)
        return destination
    }

    /// Marks a file as tried, so `isWorthCompressing` skips it.
    public static func mark(_ url: URL, attribute: String = checkedAttribute) {
        _ = setxattr(url.path, attribute, [1], 1, 0, 0)
    }

    static func hasAttribute(_ name: String, _ url: URL) -> Bool {
        getxattr(url.path, name, nil, 0, 0, 0) >= 0
    }
}
