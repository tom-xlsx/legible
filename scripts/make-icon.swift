#!/usr/bin/env swift
// Renders an SVG to a macOS .icns via NSImage (native SVG support) + iconutil.
// Usage: swift scripts/make-icon.swift Resources/icon/legible.svg build/Legible.icns
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <in.svg> <out.icns>\n".utf8))
    exit(2)
}
let svgURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

guard let image = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("make-icon: cannot read \(svgURL.path)\n".utf8))
    exit(1)
}

let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("legible-icon-\(ProcessInfo.processInfo.processIdentifier)")
let iconset = tmp.appendingPathComponent("Legible.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 2 ? "@2x" : ""
    let file = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    try render(pixels: points * scale).write(to: file)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outURL.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("make-icon: iconutil failed\n".utf8))
    exit(Int32(task.terminationStatus))
}
print("Wrote \(outURL.path)")
