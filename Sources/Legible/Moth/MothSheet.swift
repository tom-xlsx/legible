import AppKit

/// `Legible --moth-sheet=out.png [--pack=dir] [--theme=a,b]` renders every pose of a
/// pack in every theme at 24px and 96px; `--moth-validate[=dir]` checks packs.
final class MothSheetJob {
    private let options: LaunchOptions

    init?(options: LaunchOptions) {
        guard options.mothSheet != nil || options.mothValidate != nil else { return nil }
        self.options = options
    }

    func run() {
        if let target = options.mothValidate {
            validate(target)
        }
        if let out = options.mothSheet {
            render(to: URL(fileURLWithPath: out))
        }
        exit(0)
    }

    private func validate(_ target: String) {
        var failed = false
        let directories: [URL] = target.isEmpty
            ? ((try? FileManager.default.contentsOfDirectory(at: MothPack.builtInRoot, includingPropertiesForKeys: nil)) ?? [])
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
            : [URL(fileURLWithPath: target)]
        for directory in directories {
            do {
                let pack = try MothPack.load(directory: directory)
                print("ok   \(pack.name) (\(pack.kind.rawValue), \(directory.lastPathComponent))")
            } catch {
                failed = true
                print("FAIL \(directory.lastPathComponent): \(error)")
            }
        }
        if failed { exit(1) }
    }

    private func render(to output: URL) {
        let ids = options.theme?.split(separator: ",").map(String.init)
        let themes = ThemeManager.shared.themes.filter { ids == nil || ids!.contains($0.id) }
        let override: MothPack? = options.pack.flatMap { path in
            do { return try MothPack.load(directory: URL(fileURLWithPath: path)) } catch {
                FileHandle.standardError.write(Data("pack \(path): \(error)\n".utf8)); exit(1)
            }
        }
        let rig: MothPack
        do {
            rig = try MothPack.builtIn("bartholomew")
        } catch {
            FileHandle.standardError.write(Data("built-in pack: \(error)\n".utf8)); exit(1)
        }
        let wanted = options.poses?.split(separator: ",").map(String.init)
        let poses = (MothPack.requiredPoses + ["fly-2"]).filter { wanted == nil || wanted!.contains($0) }
        if let dump = ProcessInfo.processInfo.environment["MOTH_DUMP"], let theme = themes.first,
           let svg = rig.svg(pose: dump, palette: MothPack.palette(for: theme)) {
            try? svg.write(toFile: "build/dump-\(dump).svg", atomically: true, encoding: .utf8)
            print("dumped build/dump-\(dump).svg; NSImage: \(NSImage(data: Data(svg.utf8)) == nil ? "nil" : "ok")")
        }
        let sizes: [CGFloat] = [24, 96]
        let scale: CGFloat = 2, cell: CGFloat = 176, gap: CGFloat = 6, label: CGFloat = 18, rowLabel: CGFloat = 110

        // Poses across, themes down: wide sheets read better than tall ones.
        let sheetSize = NSSize(width: (rowLabel + gap + CGFloat(poses.count) * (cell + gap)) * scale,
                               height: (gap + label + CGFloat(themes.count) * (cell + gap)) * scale)
        let sheet = NSImage(size: sheetSize)
        sheet.lockFocus()
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheetSize).fill()
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11 * scale, weight: .medium), .foregroundColor: NSColor.white]

        for (ci, pose) in poses.enumerated() {
            let x = (rowLabel + gap + CGFloat(ci) * (cell + gap)) * scale
            (pose as NSString).draw(at: NSPoint(x: x, y: sheetSize.height - (gap + label) * scale + 4), withAttributes: labelAttrs)
        }
        for (ri, theme) in themes.enumerated() {
            let yTop = sheetSize.height - (gap + label + CGFloat(ri) * (cell + gap)) * scale
            (theme.name as NSString).draw(at: NSPoint(x: gap * scale, y: yTop - cell * scale / 2), withAttributes: labelAttrs)
            let pack = override ?? rig
            let palette = MothPack.palette(for: theme)
            let variants = override == nil ? MothPack.variants(for: theme) : []
            let fg = theme.variable("fg").flatMap(NSColor.init(hex:)) ?? .black
            for (ci, pose) in poses.enumerated() {
                let x = (rowLabel + gap + CGFloat(ci) * (cell + gap)) * scale
                let tile = NSRect(x: x, y: yTop - cell * scale, width: cell * scale, height: cell * scale)
                theme.backgroundColor.setFill()
                tile.fill()
                ("reading text" as NSString).draw(at: NSPoint(x: tile.minX + 6 * scale, y: tile.minY + 5 * scale),
                                                  withAttributes: [.font: NSFont.systemFont(ofSize: 10 * scale), .foregroundColor: fg])
                var cx = tile.minX + 6 * scale
                for size in sizes {
                    if let image = pack.image(pose: pose, variants: variants, palette: palette, height: size) {
                        let y = tile.maxY - 6 * scale - size * scale
                        NSGraphicsContext.current?.imageInterpolation = pack.kind == .spritesheet && !pack.isVectorSheet ? .none : .high
                        image.draw(in: NSRect(x: cx, y: y, width: size * scale, height: size * scale), from: .zero, operation: .sourceOver, fraction: 1)
                    }
                    cx += (size + 8) * scale
                }
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: output) } catch { FileHandle.standardError.write(Data("cannot write \(output.path)\n".utf8)); exit(1) }
        print("Wrote \(output.path) (\(poses.count) poses × \(themes.count) themes)")
    }
}
