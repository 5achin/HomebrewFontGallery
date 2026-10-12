import Foundation

/// The link a widget opens the app with, so the app can show the font the widget was showing:
/// "homebrewfontgallery://font/font-fira-code".
enum FontLink {
    static let scheme = "homebrewfontgallery"
    private static let host = "font"

    static func url(for token: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + token
        return components.url
    }

    /// The font a link names, or nil when the link isn't one of these.
    static func token(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host() == host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, parts[0].hasPrefix("font-") else { return nil }
        return parts[0]
    }
}
