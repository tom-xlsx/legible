import AppKit

/// One theme = one CSS file with a `:root { --var: … }` block and a header comment:
///   /* @name Oat Milk
///      @appearance light
///      @description … */
struct Theme: Equatable {
    enum Appearance: String { case light, dark }

    let id: String
    let name: String
    let appearance: Appearance
    let description: String
    let css: String
    let url: URL?
    let isBundled: Bool

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id && lhs.css == rhs.css }

    static func load(from url: URL, bundled: Bool) throws -> Theme {
        let css = try String(contentsOf: url, encoding: .utf8)
        return parse(css: css, id: url.deletingPathExtension().lastPathComponent, url: url, bundled: bundled)
    }

    static func parse(css: String, id: String, url: URL? = nil, bundled: Bool = false) -> Theme {
        let name = header("name", in: css) ?? id.replacingOccurrences(of: "-", with: " ").capitalized
        let appearance = Appearance(rawValue: header("appearance", in: css)?.lowercased() ?? "")
            ?? (backgroundColor(in: css).map { $0.isDark ? Appearance.dark : .light } ?? .light)
        return Theme(id: id, name: name, appearance: appearance,
                     description: header("description", in: css) ?? "",
                     css: css, url: url, isBundled: bundled)
    }

    var backgroundColor: NSColor { Self.backgroundColor(in: css) ?? (appearance == .dark ? .black : .white) }

    /// Value of `--name:` inside the :root block, if present.
    func variable(_ name: String) -> String? { Self.variable(name, in: css) }

    static let fallback = Theme(
        id: "fallback", name: "Fallback", appearance: .light, description: "",
        css: ":root { --bg: #ffffff; --fg: #222222; --font-body: system-ui; --font-size: 16px; --line-height: 1.6; --measure: 76ch; }",
        url: nil, isBundled: true)

    // MARK: Parsing

    private static func header(_ key: String, in css: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "@\(key)[ \\t]+([^\\n*]+)"),
              let match = regex.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)),
              let range = Range(match.range(at: 1), in: css) else { return nil }
        return css[range].trimmingCharacters(in: .whitespaces)
    }

    static func variable(_ name: String, in css: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "--\(NSRegularExpression.escapedPattern(for: name))\\s*:\\s*([^;]+);"),
              let match = regex.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)),
              let range = Range(match.range(at: 1), in: css) else { return nil }
        return css[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func backgroundColor(in css: String) -> NSColor? {
        variable("bg", in: css).flatMap(NSColor.init(hex:))
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        let shift: UInt32 = digits.count == 8 ? 8 : 0
        let r = CGFloat((value >> (16 + shift)) & 0xff) / 255
        let g = CGFloat((value >> (8 + shift)) & 0xff) / 255
        let b = CGFloat((value >> shift) & 0xff) / 255
        let a = digits.count == 8 ? CGFloat(value & 0xff) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var isDark: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance < 0.5
    }
}
