#!/usr/bin/env swift
// Tiles PNGs into one labelled grid, for reviewing every theme at a glance.
// Usage: swift scripts/contact-sheet.swift out.png [--columns 4] [--width 400] in1.png in2.png …
import AppKit
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { print("usage: contact-sheet.swift out.png [--columns N] [--width W] in.png…"); exit(2) }
let output = URL(fileURLWithPath: args.removeFirst())
var columns = 4
var tileWidth: CGFloat = 400
var inputs: [URL] = []
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--columns": columns = Int(args.removeFirst()) ?? columns
    case "--width": tileWidth = CGFloat(Double(args.removeFirst()) ?? Double(tileWidth))
    default: inputs.append(URL(fileURLWithPath: arg))
    }
}
guard !inputs.isEmpty else { exit(2) }

let images = inputs.compactMap { url -> (String, NSImage)? in
    guard let image = NSImage(contentsOf: url) else { return nil }
    return (url.deletingPathExtension().lastPathComponent, image)
}
let labelHeight: CGFloat = 26
let gap: CGFloat = 12
let aspect = images.first!.1.size.height / images.first!.1.size.width
let tileHeight = (tileWidth * aspect).rounded()
let rows = (images.count + columns - 1) / columns
let sheetSize = NSSize(width: gap + CGFloat(columns) * (tileWidth + gap),
                       height: gap + CGFloat(rows) * (tileHeight + labelHeight + gap))

let sheet = NSImage(size: sheetSize)
sheet.lockFocus()
NSColor(white: 0.5, alpha: 1).setFill()
NSRect(origin: .zero, size: sheetSize).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
for (i, (name, image)) in images.enumerated() {
    let col = CGFloat(i % columns), row = CGFloat(i / columns)
    let x = gap + col * (tileWidth + gap)
    let yTop = sheetSize.height - gap - row * (tileHeight + labelHeight + gap)
    (name as NSString).draw(at: NSPoint(x: x, y: yTop - labelHeight + 6), withAttributes: attrs)
    image.draw(in: NSRect(x: x, y: yTop - labelHeight - tileHeight, width: tileWidth, height: tileHeight),
               from: .zero, operation: .sourceOver, fraction: 1)
}
sheet.unlockFocus()
guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
print("Wrote \(output.path) (\(images.count) images)")
