import AppKit

/// An art pack for the moth: a manifest plus assets. See Resources/moth/PACK-GUIDE.md.
/// This type knows how to compose a pose into a standalone SVG (svg-rig) or pick
/// frames (spritesheet); behaviour code never touches it directly.
struct MothPack {
    enum Kind: String { case svgRig = "svg-rig", spritesheet }

    struct PartChange {
        var rotate: Double?
        var translate: (x: Double, y: Double)?
        var scale: Double?
        var visible: Bool?
        var opacity: Double?

        init(_ dict: [String: Any]) {
            rotate = dict["rotate"] as? Double
            if let t = dict["translate"] as? [Double], t.count == 2 { translate = (t[0], t[1]) }
            scale = dict["scale"] as? Double
            visible = dict["visible"] as? Bool
            opacity = dict["opacity"] as? Double
        }

        mutating func merge(_ other: PartChange) {
            if let r = other.rotate { rotate = r }
            if let t = other.translate { translate = t }
            if let s = other.scale { scale = s }
            if let v = other.visible { visible = v }
            if let o = other.opacity { opacity = o }
        }
    }

    static let requiredPoses = [
        "perch-idle", "perch-reading", "page-turn", "doze", "yawn", "wake", "startled", "cling",
        "smooth-down", "disapprove", "glance", "nod", "magnifier", "wave", "close-book", "take-off", "fly", "land",
    ]
    static let requiredAnchors = ["feet", "centre", "eyeLeft", "eyeRight", "book"]
    static let paletteTokens = ["moth-body", "moth-wing", "moth-wing-shade", "moth-wing-mark", "moth-eye",
                                "moth-eye-white", "moth-glasses", "moth-book", "moth-page"]

    let directory: URL
    let manifest: [String: Any]
    let name: String
    let kind: Kind
    let size: CGFloat
    let svgSource: String?          // svg-rig, or a spritesheet whose asset is an SVG of frame groups
    let sheet: NSImage?             // spritesheet with a PNG asset
    let frameIndex: [String: Int]   // spritesheet
    var isVectorSheet: Bool { kind == .spritesheet && svgSource != nil }

    struct LoadError: Error, CustomStringConvertible {
        let problems: [String]
        var description: String { problems.joined(separator: "; ") }
    }

    static func load(directory: URL) throws -> MothPack {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw LoadError(problems: ["no manifest.json in \(directory.path)"])
        }
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError(problems: ["manifest.json is not a JSON object"])
        }
        var problems: [String] = []
        let kindName = manifest["type"] as? String ?? ""
        guard let kind = Kind(rawValue: kindName) else {
            throw LoadError(problems: ["unknown pack type \"\(kindName)\" (expected svg-rig or spritesheet)"])
        }
        let name = manifest["name"] as? String ?? directory.lastPathComponent
        let size = CGFloat((manifest["size"] as? Double) ?? 0)
        if !(12...96).contains(size) { problems.append("size must be between 12 and 96 (got \(Int(size)))") }
        let assetName = manifest["asset"] as? String ?? ""
        let assetURL = directory.appendingPathComponent(assetName)
        if assetName.isEmpty || !FileManager.default.fileExists(atPath: assetURL.path) {
            problems.append("asset \"\(assetName)\" does not exist")
        }
        let anchors = manifest["anchors"] as? [String: Any] ?? [:]
        for a in requiredAnchors where (anchors[a] as? [Double])?.count != 2 {
            problems.append("anchor \"\(a)\" missing or not [x, y]")
        }
        let poses = manifest["poses"] as? [String: Any] ?? [:]
        let missing = requiredPoses.filter { poses[$0] == nil }
        if !missing.isEmpty { problems.append("missing poses: \(missing.joined(separator: ", "))") }

        var svgSource: String?
        var sheet: NSImage?
        var frameIndex: [String: Int] = [:]
        switch kind {
        case .svgRig:
            svgSource = try? String(contentsOf: assetURL, encoding: .utf8)
            if svgSource == nil { problems.append("cannot read \(assetName)") }
            let parts = manifest["parts"] as? [String: Any] ?? [:]
            if parts.isEmpty { problems.append("svg-rig packs need a parts table") }
            if let svg = svgSource {
                for id in parts.keys where !svg.contains("id=\"\(id)\"") {
                    problems.append("part \"\(id)\" is not in the SVG")
                }
                for (pose, spec) in poses {
                    for part in (spec as? [String: Any] ?? [:]).keys where parts[part] == nil {
                        problems.append("pose \"\(pose)\" changes unknown part \"\(part)\"")
                    }
                }
            }
        case .spritesheet:
            let indexName = manifest["frameIndex"] as? String ?? "frames.json"
            if let data = try? Data(contentsOf: directory.appendingPathComponent(indexName)),
               let index = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                frameIndex = index
            } else {
                problems.append("cannot read frame index \(indexName)")
            }
            let frameSize = manifest["frameSize"] as? [Double] ?? []
            if frameSize.count != 2 { problems.append("frameSize must be [width, height]") }
            if assetURL.pathExtension.lowercased() == "svg" {
                // Frames are <g id="name"> groups coloured with the palette tokens.
                svgSource = try? String(contentsOf: assetURL, encoding: .utf8)
                if svgSource == nil { problems.append("cannot read \(assetName)") }
                for (pose, spec) in poses {
                    for frame in (spec as? [String: Any])?["frames"] as? [String] ?? [] {
                        if frameIndex[frame] == nil { problems.append("pose \"\(pose)\" uses unknown frame \"\(frame)\"") }
                        else if let svg = svgSource, !svg.contains("<g id=\"\(frame)\"") { problems.append("frame \"\(frame)\" is not in \(assetName)") }
                    }
                }
            } else {
                sheet = NSImage(contentsOf: assetURL)
                if sheet == nil { problems.append("cannot read \(assetName) as an image") }
                if let sheet, frameSize.count == 2 {
                    let columns = Int(sheet.size.width / CGFloat(frameSize[0]))
                    for (pose, spec) in poses {
                        for frame in (spec as? [String: Any])?["frames"] as? [String] ?? [] {
                            guard let column = frameIndex[frame] else { problems.append("pose \"\(pose)\" uses unknown frame \"\(frame)\""); continue }
                            if column >= columns { problems.append("frame \"\(frame)\" (column \(column)) is outside the sheet") }
                        }
                    }
                }
            }
        }
        if !problems.isEmpty { throw LoadError(problems: problems) }
        return MothPack(directory: directory, manifest: manifest, name: name, kind: kind, size: size,
                        svgSource: svgSource, sheet: sheet, frameIndex: frameIndex)
    }

    // MARK: Palette

    /// Derives the moth tokens from a theme; the theme's own --moth-* values win.
    static func palette(for theme: Theme) -> [String: String] {
        func rgb(_ name: String, _ fallback: String) -> NSColor {
            theme.variable(name).flatMap(NSColor.init(hex:)) ?? NSColor(hex: fallback)!
        }
        let bg = rgb("bg", "#ffffff"), fg = rgb("fg", "#222222"), muted = rgb("fg-muted", "#666666"), link = rgb("link", "#3366aa")
        let dark = bg.isDark
        let white = NSColor(hex: "#ffffff")!
        // Body darker than wings on dark themes (so the eyes and glasses read), darker still on light ones.
        var p: [String: String] = [
            "moth-body": dark ? muted.mixed(with: bg, 0.2).hexString : muted.mixed(with: fg, 0.3).hexString,
            "moth-wing": bg.mixed(with: muted, dark ? 0.62 : 0.42).hexString,
            "moth-wing-shade": bg.mixed(with: muted, dark ? 0.45 : 0.58).hexString,
            "moth-wing-mark": dark ? bg.mixed(with: muted, 0.25).hexString : muted.mixed(with: fg, 0.2).hexString,
            "moth-eye": fg.hexString,
            "moth-eye-white": bg.mixed(with: dark ? fg : white, dark ? 0.75 : 0.6).hexString,
            "moth-glasses": link.hexString,
            "moth-book": link.hexString,
            "moth-page": bg.mixed(with: dark ? fg : white, dark ? 0.7 : 0.5).hexString,
        ]
        for token in paletteTokens {
            if let override = theme.variable(token) { p[token] = override }
        }
        return p
    }

    // MARK: svg-rig composition

    /// A standalone SVG for one pose, with variants and palette applied.
    func svg(pose: String, variants: Set<String> = [], palette: [String: String], lookAt: (x: Double, y: Double)? = nil) -> String? {
        guard kind == .svgRig, var svg = svgSource else { return nil }
        let parts = manifest["parts"] as? [String: [String: Any]] ?? [:]
        var changes: [String: PartChange] = [:]
        for (id, spec) in parts {
            var change = PartChange([:])
            change.visible = !((spec["hidden"] as? Bool) ?? false)
            changes[id] = change
        }
        let variantTable = manifest["variants"] as? [String: [String: [String: Any]]] ?? [:]
        for v in variants {
            for (id, spec) in variantTable[v] ?? [:] { changes[id, default: PartChange([:])].merge(PartChange(spec)) }
        }
        if let poseSpec = (manifest["poses"] as? [String: [String: [String: Any]]])?[pose] {
            for (id, spec) in poseSpec { changes[id, default: PartChange([:])].merge(PartChange(spec)) }
        }
        for (id, change) in changes {
            guard let spec = parts[id], let pivot = spec["pivot"] as? [Double], pivot.count == 2 else { continue }
            var transform = ""
            if change.rotate != nil || change.scale != nil || change.translate != nil {
                transform = "translate(\(pivot[0]) \(pivot[1]))"
                if let r = change.rotate { transform += " rotate(\(r))" }
                if let s = change.scale { transform += " scale(\(s))" }
                transform += " translate(\(-pivot[0]) \(-pivot[1]))"
                if let t = change.translate { transform = "translate(\(t.x) \(t.y)) " + transform }
            }
            if change.visible == false {
                // Hidden parts are removed outright: NSImage's SVG renderer ignores display/visibility on groups.
                let open = "<g id=\"\(id)\""
                if let start = svg.range(of: open), let end = svg.range(of: "</g>", range: start.upperBound..<svg.endIndex) {
                    svg.removeSubrange(start.lowerBound..<end.upperBound)
                }
                continue
            }
            var attrs = ""
            if !transform.isEmpty { attrs += " transform=\"\(transform)\"" }
            if let o = change.opacity { attrs += " opacity=\"\(o)\"" }
            svg = svg.replacingOccurrences(of: "<g id=\"\(id)\"", with: "<g id=\"\(id)\"\(attrs)")
        }
        if let lookAt, let pupils = manifest["pupils"] as? [String] {
            let range = (manifest["pupilRange"] as? Double) ?? 1
            for pupil in pupils {
                if let regex = try? NSRegularExpression(pattern: "id=\"\(pupil)\" cx=\"([\\d.]+)\" cy=\"([\\d.]+)\""),
                   let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
                   let cxR = Range(match.range(at: 1), in: svg), let cyR = Range(match.range(at: 2), in: svg),
                   let cx = Double(svg[cxR]), let cy = Double(svg[cyR]) {
                    let replacement = "id=\"\(pupil)\" cx=\"\(cx + lookAt.x * range)\" cy=\"\(cy + lookAt.y * range)\""
                    svg = (svg as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }
        for (token, value) in palette { svg = svg.replacingOccurrences(of: "var(--\(token))", with: value) }
        return svg
    }

    /// Frame names a spritesheet pose cycles through.
    func frameNames(pose: String) -> [String] {
        let name = pose == "fly-2" ? "fly" : pose
        let names = ((manifest["poses"] as? [String: [String: Any]])?[name]?["frames"] as? [String]) ?? []
        return pose == "fly-2" ? Array(names.dropFirst()) : names
    }

    /// A standalone SVG showing one frame of a vector spritesheet.
    func frameSVG(_ frame: String, palette: [String: String]) -> String? {
        guard isVectorSheet, var svg = svgSource else { return nil }
        for other in frameIndex.keys where other != frame {
            let open = "<g id=\"\(other)\""
            if let start = svg.range(of: open), let end = svg.range(of: "</g>", range: start.upperBound..<svg.endIndex) {
                svg.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        for (token, value) in palette { svg = svg.replacingOccurrences(of: "var(--\(token))", with: value) }
        return svg
    }

    func image(pose: String, variants: Set<String>, palette: [String: String], height: CGFloat) -> NSImage? {
        if isVectorSheet {
            guard let frame = frameNames(pose: pose).first, let svg = frameSVG(frame, palette: palette),
                  let image = NSImage(data: Data(svg.utf8)) else { return nil }
            image.size = NSSize(width: height, height: height)
            return image
        }
        switch kind {
        case .svgRig:
            guard let svg = svg(pose: pose, variants: variants, palette: palette), let image = NSImage(data: Data(svg.utf8)) else { return nil }
            image.size = NSSize(width: height, height: height)
            return image
        case .spritesheet:
            let frame = pose == "fly-2" ? frames(pose: "fly").dropFirst().first : frames(pose: pose).first
            return frame.map { frame in
                let image = NSImage(size: NSSize(width: height, height: height), flipped: false) { rect in
                    NSGraphicsContext.current?.imageInterpolation = .none
                    frame.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                    return true
                }
                return image
            }
        }
    }

    /// Frame images for a spritesheet pose, in order.
    func frames(pose: String) -> [NSImage] {
        guard kind == .spritesheet, let sheet,
              let spec = (manifest["poses"] as? [String: [String: Any]])?[pose],
              let names = spec["frames"] as? [String],
              let frameSize = manifest["frameSize"] as? [Double], frameSize.count == 2 else { return [] }
        let w = CGFloat(frameSize[0]), h = CGFloat(frameSize[1])
        return names.compactMap { name in
            guard let column = frameIndex[name] else { return nil }
            let source = NSRect(x: CGFloat(column) * w, y: 0, width: w, height: h)
            let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
                NSGraphicsContext.current?.imageInterpolation = .none
                sheet.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
                return true
            }
            return image
        }
    }

    // MARK: Built-in packs

    static var builtInRoot: URL { AppInfo.resourcesRoot.appendingPathComponent("moth", isDirectory: true) }
    static var userDirectory: URL { AppInfo.supportDirectory.appendingPathComponent("Moth", isDirectory: true) }

    static func builtIn(_ folder: String) throws -> MothPack {
        try load(directory: builtInRoot.appendingPathComponent(folder))
    }

    /// The pack in use: a valid user pack, otherwise the built-in one.
    static func current() -> (pack: MothPack, problem: String?) {
        let user = userDirectory
        if FileManager.default.fileExists(atPath: user.appendingPathComponent("manifest.json").path) {
            do { return (try load(directory: user), nil) } catch {
                return (try! builtIn("bartholomew"), "Moth pack in \(user.path): \(error). Using the built-in moth.")
            }
        }
        return (try! builtIn("bartholomew"), nil)
    }

    /// Variant flags the app requests for a theme.
    static func variants(for theme: Theme) -> Set<String> {
        switch theme.id {
        case "big-breakfast": return ["glasses-large"]
        case "decaf": return ["eyes-drowsy"]
        case "midnight-snack": return ["body-faint"]
        default: return []
        }
    }
}

extension NSColor {
    func mixed(with other: NSColor, _ t: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }
}
