import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Draws a font's thumbnail: a short sample set in the font, as a picture.
enum FontThumbnailRenderer {
    static let sample = "Aa"
    /// The picture's size in points. It fills the upper part of a card in the grid.
    static let size = CGSize(width: 98, height: 93)
    static let fontSize: CGFloat = 44
    /// Pixels per point, enough for a Retina display.
    static let scale: CGFloat = 2
    private static let margin: CGFloat = 6

    /// A PNG of the sample in black on a clear background, so it can be tinted for light or dark mode.
    static func png(for face: FontFace) -> Data? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)

        var line = self.line(face: face, fontSize: fontSize)
        var bounds = CTLineGetBoundsWithOptions(line, [])
        // Shrink a wide sample to fit, as far as 40%.
        let available = size.width - 2 * margin
        if bounds.width > available {
            line = self.line(face: face, fontSize: fontSize * max(0.4, available / bounds.width))
            bounds = CTLineGetBoundsWithOptions(line, [])
        }
        // Centre the line by its ascent and descent, as text in a view is centred.
        context.textPosition = CGPoint(x: (size.width - bounds.width) / 2 - bounds.minX,
                                       y: (size.height - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func line(face: FontFace, fontSize: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): face.font(size: fontSize),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: attributes))
    }

    /// Reads a saved thumbnail back as a picture that takes on the colour of the text around it.
    static func image(fromPNG data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        image.size = size
        image.isTemplate = true
        return image
    }
}

/// Supplies the grid's thumbnails. Each is drawn once and saved as a small picture in the app's
/// cache. A font that isn't installed is downloaded for that, a few at a time as thumbnails
/// scroll into view, and the download is deleted as soon as its picture is saved.
actor FontThumbnails {
    static let shared = FontThumbnails()

    static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HomebrewFontGallery")
        .appendingPathComponent("Thumbnails")

    /// Ends every saved thumbnail's name. It carries the picture's size, so pictures
    /// drawn for a different size of card aren't used.
    private static let suffix = "-\(Int(FontThumbnailRenderer.size.width))x\(Int(FontThumbnailRenderer.size.height)).png"

    /// Deletes thumbnails saved by a version of the app that drew them at another size.
    static func removeOutdated() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !file.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The thumbnails that ship inside the app, one picture per font, named by the font's token.
    /// `scripts/update-thumbnails.sh` fills this folder, so only fonts Homebrew has added since
    /// need their thumbnail drawn on this Mac.
    static let bundledDirectory = Bundle.main.url(forResource: "Thumbnails", withExtension: "bundle")

    static func bundledPNG(for font: FontCask) -> Data? {
        guard let bundledDirectory else { return nil }
        return try? Data(contentsOf: bundledDirectory.appendingPathComponent("\(font.token).png"))
    }

    private let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()
    /// Fonts with no file to show, or whose file couldn't be fetched or read, since the app opened.
    private var unavailable = Set<String>()
    private let downloads = Limiter(limit: 6)

    /// The font's thumbnail, or nil when the font can only be seen after installing it.
    func thumbnail(for font: FontCask) async -> NSImage? {
        let name = "\(font.token)-\(FontPreview.cacheKey(for: font))\(FontThumbnails.suffix)"
        if let image = images.object(forKey: name as NSString) {
            return image
        }
        let file = FontThumbnails.directory.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), let image = FontThumbnailRenderer.image(fromPNG: data) {
            images.setObject(image, forKey: name as NSString)
            return image
        }
        // A thumbnail that shipped with the app saves downloading the font at all.
        if let data = FontThumbnails.bundledPNG(for: font), let image = FontThumbnailRenderer.image(fromPNG: data) {
            images.setObject(image, forKey: name as NSString)
            return image
        }
        guard !unavailable.contains(name) else { return nil }

        guard let data = await render(font) else {
            // A thumbnail that scrolled away before it was drawn is tried again when it comes back.
            if !Task.isCancelled {
                unavailable.insert(name)
            }
            return nil
        }
        try? FileManager.default.createDirectory(at: FontThumbnails.directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        guard let image = FontThumbnailRenderer.image(fromPNG: data) else { return nil }
        images.setObject(image, forKey: name as NSString)
        return image
    }

    /// Draws the thumbnail from the installed font, or from a download that is then deleted.
    func render(_ font: FontCask) async -> Data? {
        if font.isInstalled, let name = FontCask.representativeFile(in: font.fontFiles.map(\.lastPathComponent)),
           let file = font.fontFiles.first(where: { $0.lastPathComponent == name }),
           let face = FontPreview.faces(in: [file]).first {
            return FontThumbnailRenderer.png(for: face)
        }
        guard font.previewDownloadURL != nil else { return nil }

        await downloads.acquire()
        defer { Task { await downloads.release() } }
        // The thumbnail may have scrolled away while it waited its turn.
        guard !Task.isCancelled, let file = try? await FontPreview.download(font) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        return FontPreview.faces(in: [file]).first.flatMap(FontThumbnailRenderer.png(for:))
    }

    /// Lets a fixed number of callers through at a time, in the order they asked.
    private actor Limiter {
        private var available: Int
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) {
            available = limit
        }

        func acquire() async {
            if available > 0 {
                available -= 1
                return
            }
            await withCheckedContinuation { waiting.append($0) }
        }

        func release() {
            if waiting.isEmpty {
                available += 1
            } else {
                waiting.removeFirst().resume()
            }
        }
    }
}
