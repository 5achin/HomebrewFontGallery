import Foundation

/// Finds one face of each font for the grid's thumbnails, and remembers it while the app runs.
/// Fonts that aren't installed are downloaded a few at a time as their thumbnails scroll into view.
actor FontThumbnails {
    static let shared = FontThumbnails()

    private struct Key: Hashable {
        let token: String
        let installedVersion: String?
    }

    private enum Entry {
        case face(FontFace)
        /// The font has no file to show, or its file couldn't be read.
        case unavailable
    }

    private var entries: [Key: Entry] = [:]
    private let downloads = Limiter(limit: 4)

    /// The face to draw the font's thumbnail with, or nil when it can only be seen after installing.
    func face(for font: FontCask) async -> FontFace? {
        let key = Key(token: font.token, installedVersion: font.installedVersion)
        if let entry = entries[key] {
            if case .face(let face) = entry { return face }
            return nil
        }

        if font.isInstalled, let name = FontCask.representativeFile(in: font.fontFiles.map(\.lastPathComponent)),
           let file = font.fontFiles.first(where: { $0.lastPathComponent == name }),
           let face = FontPreview.faces(in: [file]).first {
            entries[key] = .face(face)
            return face
        }
        guard font.previewDownloadURL != nil else {
            entries[key] = .unavailable
            return nil
        }

        await downloads.acquire()
        defer { Task { await downloads.release() } }
        // The thumbnail may have scrolled away while it waited its turn.
        guard !Task.isCancelled else { return nil }
        do {
            let file = try await FontPreview.downloadedFile(for: font)
            let face = FontPreview.faces(in: [file]).first
            entries[key] = face.map(Entry.face) ?? .unavailable
            return face
        } catch {
            // A cancelled download is tried again the next time the thumbnail appears.
            if !Task.isCancelled {
                entries[key] = .unavailable
            }
            return nil
        }
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
