import Foundation

/// Pure functions that build `brew` arguments and turn its output into model types.
enum BrewParsing {
    static let fontPrefix = "font-"

    // MARK: Arguments

    static let listAllArguments = ["casks"]

    static func infoArguments(tokens: [String]) -> [String] {
        ["info", "--json=v2", "--cask"] + tokens
    }

    static func installArguments(token: String) -> [String] {
        ["install", "--cask", token]
    }

    static func uninstallArguments(token: String) -> [String] {
        ["uninstall", "--cask", token]
    }

    // MARK: Output

    /// Picks the font tokens out of `brew casks`, which prints one token per line.
    static func fontTokens(fromCaskList output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { isFontToken($0) && seen.insert($0).inserted }
            .sorted()
    }

    /// A token is only ever passed to `brew` as an argument, so it must not look like an option.
    static func isFontToken(_ token: String) -> Bool {
        guard token.hasPrefix(fontPrefix), token.count > fontPrefix.count else { return false }
        return token.unicodeScalars.allSatisfy { allowedTokenScalars.contains($0) }
    }

    private static let allowedTokenScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.@+")

    /// Decodes the output of `brew info --json=v2 --cask`.
    static func fonts(fromInfoJSON data: Data) throws -> [FontCask] {
        let info = try JSONDecoder().decode(Info.self, from: data)
        return info.casks.filter { isFontToken($0.token) }.map(\.font)
    }

    private struct Info: Decodable {
        let casks: [Cask]
    }

    private struct Cask: Decodable {
        let token: String
        let name: [String]?
        let desc: String?
        let homepage: String?
        let url: String?
        let sha256: String?
        let version: String?
        let installed: String?
        let artifacts: [Artifact]?
        let deprecated: Bool?
        let disabled: Bool?

        var font: FontCask {
            let names = (name ?? []).filter { !$0.isEmpty }
            let artifacts = artifacts ?? []
            return FontCask(
                token: token,
                name: names.first ?? BrewParsing.displayName(fromToken: token),
                alternateNames: Array(names.dropFirst()),
                summary: desc.flatMap { $0.isEmpty ? nil : $0 },
                homepage: homepage.flatMap(URL.init(string:)),
                downloadURL: url.flatMap(URL.init(string:)),
                sha256: sha256.flatMap { BrewParsing.isSHA256($0) ? $0.lowercased() : nil },
                version: version ?? "",
                installedVersion: installed.flatMap { $0.isEmpty ? nil : $0 },
                fontFiles: artifacts.compactMap(\.fontTarget).map { URL(fileURLWithPath: $0) },
                needsInstaller: artifacts.contains { $0.isInstallerPackage },
                isDeprecated: deprecated ?? false,
                isDisabled: disabled ?? false
            )
        }
    }

    /// Artifacts come in several shapes. Only font files and installer packages matter here.
    private struct Artifact: Decodable {
        let fontTarget: String?
        let isInstallerPackage: Bool

        private enum CodingKeys: String, CodingKey {
            case font, target, pkg
        }

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            let isFont = container?.contains(.font) ?? false
            fontTarget = isFont ? (try? container?.decode(String.self, forKey: .target)) : nil
            isInstallerPackage = container?.contains(.pkg) ?? false
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    /// "font-fira-code" becomes "Fira Code", for the rare font Homebrew gives no name.
    static func displayName(fromToken token: String) -> String {
        token.dropFirst(token.hasPrefix(fontPrefix) ? fontPrefix.count : 0)
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
