#!/usr/bin/env swift
// Draws the app icon's two layers into HomebrewFontGallery/AppIcon.icon/Assets:
// four tiles in a grid, and one letter for each tile, each set in a different font.
// Icon Composer's icon.json supplies the glass, the shadows and the background.
//
//   swift scripts/draw-icon.swift
import CoreText
import Foundation

let canvas = 1024.0
let tileSide = 428.0
let gap = 40.0
/// The icon's own corner radius on this canvas.
let iconRadius = 230.0
/// The most room a letter may take up inside its tile.
let letterBox = 250.0
let letterColour = "#6A5FD6"

/// A letter and the font it is set in, for each tile, row by row.
let letters: [(String, String)] = [
    ("A", "Didot-Bold"),
    ("a", "Futura-Bold"),
    ("a", "SnellRoundhand-Black"),
    ("A", "Rockwell-Bold"),
]

func number(_ value: Double) -> String {
    String(format: "%.1f", value)
}

let origin = (canvas - 2 * tileSide - gap) / 2
/// The tiles' corners follow the icon's, so the bezel is the same width all the way round.
let radius = iconRadius - origin
let tiles: [(x: Double, y: Double)] = (0..<4).map { index in
    (origin + Double(index % 2) * (tileSide + gap), origin + Double(index / 2) * (tileSide + gap))
}

func tilePath(x: Double, y: Double) -> String {
    let s = tileSide, r = radius
    return "M\(number(x + r)) \(number(y)) H\(number(x + s - r)) A\(number(r)) \(number(r)) 0 0 1 \(number(x + s)) \(number(y + r)) "
        + "V\(number(y + s - r)) A\(number(r)) \(number(r)) 0 0 1 \(number(x + s - r)) \(number(y + s)) "
        + "H\(number(x + r)) A\(number(r)) \(number(r)) 0 0 1 \(number(x)) \(number(y + s - r)) "
        + "V\(number(y + r)) A\(number(r)) \(number(r)) 0 0 1 \(number(x + r)) \(number(y)) Z"
}

/// The outline of one letter, scaled to fit the letter box and centred on a tile.
func letterPath(_ letter: String, fontName: String, centreX: Double, centreY: Double) -> String {
    let font = CTFontCreateWithName(fontName as CFString, 200, nil)
    guard CTFontCopyPostScriptName(font) as String == fontName else {
        fatalError("\(fontName) isn't installed on this Mac")
    }
    var character = Array(letter.utf16)
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), let outline = CTFontCreatePathForGlyph(font, glyph, nil) else {
        fatalError("\(fontName) has no “\(letter)”")
    }
    let bounds = outline.boundingBoxOfPath
    let scale = letterBox / max(bounds.width, bounds.height)
    // Font outlines have y pointing up, and SVG has it pointing down.
    func point(_ p: CGPoint) -> String {
        let x = centreX + (p.x - bounds.midX) * scale
        let y = centreY - (p.y - bounds.midY) * scale
        return "\(number(x)) \(number(y))"
    }
    var commands: [String] = []
    outline.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: commands.append("M\(point(points[0]))")
        case .addLineToPoint: commands.append("L\(point(points[0]))")
        case .addQuadCurveToPoint: commands.append("Q\(point(points[0])) \(point(points[1]))")
        case .addCurveToPoint: commands.append("C\(point(points[0])) \(point(points[1])) \(point(points[2]))")
        case .closeSubpath: commands.append("Z")
        @unknown default: break
        }
    }
    return commands.joined(separator: " ")
}

func svg(_ paths: [String], fill: String) -> String {
    let body = paths.map { "  <path d=\"\($0)\" fill=\"\(fill)\"/>" }.joined(separator: "\n")
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n\(body)\n</svg>\n"
}

let assets = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("../HomebrewFontGallery/AppIcon.icon/Assets").standardizedFileURL
let tileLayer = svg(tiles.map { tilePath(x: $0.x, y: $0.y) }, fill: "#FFFFFF")
let letterLayer = svg(zip(letters, tiles).map { letter, tile in
    letterPath(letter.0, fontName: letter.1, centreX: tile.x + tileSide / 2, centreY: tile.y + tileSide / 2)
}, fill: letterColour)
try tileLayer.write(to: assets.appendingPathComponent("tiles.svg"), atomically: true, encoding: .utf8)
try letterLayer.write(to: assets.appendingPathComponent("letters.svg"), atomically: true, encoding: .utf8)
print("Wrote tiles.svg and letters.svg to \(assets.path)")
