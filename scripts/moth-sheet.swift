#!/usr/bin/env swift
// Renders moth SVGs onto theme backgrounds at several sizes into one labelled sheet.
// Usage: swift scripts/moth-sheet.swift out.png --themes oat-milk,burnt-toast --sizes 16,24,96 a.svg b.svg …
// Palette tokens (--moth-*) are derived from each theme's variables, the same way the app does.
import AppKit
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: args.removeFirst())
var themeIDs = ["oat-milk", "burnt-toast", "hashbrown"]
var sizes: [CGFloat] = [16, 24, 96]
var svgs: [URL] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--themes": themeIDs = args.removeFirst().split(separator: ",").map(String.init)
    case "--sizes": sizes = args.removeFirst().split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
    default: svgs.append(URL(fileURLWithPath: a))
    }
}

struct RGB { var r: CGFloat; var g: CGFloat; var b: CGFloat
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces); h.removeFirst()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt32(h, radix: 16) ?? 0
        r = CGFloat((v >> 16) & 0xff) / 255; g = CGFloat((v >> 8) & 0xff) / 255; b = CGFloat(v & 0xff) / 255
    }
    init(r: CGFloat, g: CGFloat, b: CGFloat) { self.r = r; self.g = g; self.b = b }
    var hex: String { String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255)) }
    var luminance: CGFloat {
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

func themeVars(_ id: String) -> [String: String] {
    let url = URL(fileURLWithPath: "Resources/themes/\(id).css")
    let css = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    var vars: [String: String] = [:]
    let regex = try! NSRegularExpression(pattern: "--([\\w-]+)\\s*:\\s*([^;]+);")
    for m in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
        vars[String(css[Range(m.range(at: 1), in: css)!])] = css[Range(m.range(at: 2), in: css)!].trimmingCharacters(in: .whitespaces)
    }
    return vars
}

/// Moth palette derived from theme variables; a theme may override any --moth-* token.
func mothPalette(_ v: [String: String]) -> [String: String] {
    let bg = RGB(hex: v["bg"] ?? "#ffffff"), fg = RGB(hex: v["fg"] ?? "#222222")
    let muted = RGB(hex: v["fg-muted"] ?? "#666666"), link = RGB(hex: v["link"] ?? "#3366aa")
    let dark = bg.luminance < 0.35
    var p: [String: String] = [
        "moth-body": muted.mix(fg, 0.25).hex,
        "moth-wing": bg.mix(muted, dark ? 0.55 : 0.42).hex,
        "moth-wing-mark": muted.mix(fg, 0.1).hex,
        "moth-eye": fg.hex,
        "moth-eye-white": bg.mix(dark ? fg : RGB(hex: "#ffffff"), dark ? 0.75 : 0.6).hex,
        "moth-glasses": link.hex,
        "moth-book": link.hex,
        "moth-page": bg.mix(dark ? fg : RGB(hex: "#ffffff"), dark ? 0.7 : 0.5).hex,
    ]
    for (k, val) in v where k.hasPrefix("moth-") { p[k] = val }
    return p
}

func render(svg: String, palette: [String: String], size: CGFloat) -> NSImage? {
    var text = svg
    for (k, val) in palette { text = text.replacingOccurrences(of: "var(--\(k))", with: val) }
    guard let image = NSImage(data: Data(text.utf8)) else { return nil }
    image.size = NSSize(width: size, height: size)
    return image
}

let scale: CGFloat = 2   // render at 2x for a Retina-faithful sheet
let cell: CGFloat = 176, gap: CGFloat = 8, label: CGFloat = 20
let cols = CGFloat(themeIDs.count)
let rows = CGFloat(svgs.count)
let sheet = NSImage(size: NSSize(width: (gap + cols * (cell + gap)) * scale, height: (gap + rows * (cell + label + gap)) * scale))
sheet.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
NSColor(white: 0.5, alpha: 1).setFill()
NSRect(origin: .zero, size: sheet.size).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12 * scale, weight: .medium), .foregroundColor: NSColor.white]
for (ri, svgURL) in svgs.enumerated() {
    let svg = (try? String(contentsOf: svgURL, encoding: .utf8)) ?? ""
    for (ci, id) in themeIDs.enumerated() {
        let vars = themeVars(id)
        let palette = mothPalette(vars)
        let x = (gap + CGFloat(ci) * (cell + gap)) * scale
        let yTop = sheet.size.height - (gap + CGFloat(ri) * (cell + label + gap)) * scale
        ("\(svgURL.deletingPathExtension().lastPathComponent) · \(id)" as NSString).draw(at: NSPoint(x: x, y: yTop - label * scale + 4), withAttributes: attrs)
        let tile = NSRect(x: x, y: yTop - (label + cell) * scale, width: cell * scale, height: cell * scale)
        RGB(hex: vars["bg"] ?? "#ffffff").nsColor.setFill()
        tile.fill()
        // a line of body text so overlap and contrast can be judged
        let textAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11 * scale), .foregroundColor: RGB(hex: vars["fg"] ?? "#222").nsColor]
        ("reading text" as NSString).draw(at: NSPoint(x: tile.minX + 6 * scale, y: tile.minY + 6 * scale), withAttributes: textAttrs)
        var cx = tile.minX + 6 * scale
        for size in sizes {
            if let img = render(svg: svg, palette: palette, size: size) {
                let y = tile.maxY - 6 * scale - size * scale
                img.draw(in: NSRect(x: cx, y: y, width: size * scale, height: size * scale), from: .zero, operation: .sourceOver, fraction: 1)
            }
            cx += (size + 6) * scale
        }
    }
}
sheet.unlockFocus()
guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
print("Wrote \(output.path)")
