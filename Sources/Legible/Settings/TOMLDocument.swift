import Foundation

/// The subset of TOML Legible's settings file uses: comments, blank lines,
/// `[tables]`, and `key = value` where the value is a string, integer, float
/// or boolean. Arrays, inline tables, multi-line strings, dates and dotted
/// keys are reported as errors naming the line; nothing is ever silently
/// dropped or rewritten.
///
/// The document keeps every line as written, so changing one value patches
/// exactly that line and comments, order and unknown keys all survive.
struct TOMLDocument: Equatable {
    enum Value: Equatable {
        case string(String)
        case int(Int)
        case float(Double)
        case bool(Bool)

        var serialized: String {
            switch self {
            case .string(let s): return "\"" + Self.escape(s) + "\""
            case .int(let i): return String(i)
            case .float(let d):
                if d.isNaN { return "nan" }
                if d.isInfinite { return d < 0 ? "-inf" : "inf" }
                if d == d.rounded() && abs(d) < 1e15 { return String(format: "%.1f", d) }
                return String(d)
            case .bool(let b): return b ? "true" : "false"
            }
        }

        private static func escape(_ s: String) -> String {
            var out = ""
            for scalar in s.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                case let c where c.value < 0x20 || c.value == 0x7F: out += String(format: "\\u%04X", c.value)
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out
        }
    }

    struct ParseError: Error, CustomStringConvertible, Equatable {
        let line: Int      // 1-based
        let message: String
        var description: String { "line \(line): \(message)" }
    }

    private enum Line: Equatable {
        case verbatim(String)                                   // blank or comment-only
        case table(name: String, text: String)
        case keyValue(table: String, key: String, value: Value, prefix: String, raw: String, suffix: String)
    }

    private var lines: [Line]
    private var newline: String
    private var endsWithNewline: Bool

    /// Root table keys live in table "".
    private(set) var tables: [String: [String: Value]] = [:]

    // MARK: Parsing

    init(text: String) throws {
        newline = text.contains("\r\n") ? "\r\n" : "\n"
        var raw = text.components(separatedBy: newline)
        endsWithNewline = text.isEmpty || text.hasSuffix(newline)
        if raw.last == "" { raw.removeLast() }   // a trailing newline, restored on output
        var result: [Line] = []
        var current = ""
        var tables: [String: [String: Value]] = ["": [:]]

        for (index, line) in raw.enumerated() {
            let number = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                result.append(.verbatim(line))
                continue
            }
            if trimmed.hasPrefix("[") {
                if trimmed.hasPrefix("[[") {
                    throw ParseError(line: number, message: "arrays of tables ([[…]]) are not supported")
                }
                guard let close = trimmed.firstIndex(of: "]") else {
                    throw ParseError(line: number, message: "table header is missing its closing ]")
                }
                let name = trimmed[trimmed.index(after: trimmed.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
                guard rest.isEmpty || rest.hasPrefix("#") else {
                    throw ParseError(line: number, message: "unexpected text after table header")
                }
                guard Self.isBareKey(name) else {
                    throw ParseError(line: number, message: "table name \"\(name)\" must be a plain name (letters, digits, - and _)")
                }
                if tables[name] != nil {
                    throw ParseError(line: number, message: "table [\(name)] is defined twice")
                }
                tables[name] = [:]
                current = name
                result.append(.table(name: name, text: line))
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                throw ParseError(line: number, message: "expected key = value")
            }
            let keyPart = line[..<eq]
            let key = keyPart.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw ParseError(line: number, message: "missing key before =") }
            guard Self.isBareKey(key) else {
                if key.contains(".") { throw ParseError(line: number, message: "dotted keys (\(key)) are not supported") }
                throw ParseError(line: number, message: "key \"\(key)\" must be a plain name (letters, digits, - and _)")
            }
            let afterEq = line[line.index(after: eq)...]
            let (value, valueText, suffix) = try Self.parseValue(String(afterEq), line: number)
            if tables[current]?[key] != nil {
                throw ParseError(line: number, message: "key \"\(key)\" is defined twice in [\(current)]")
            }
            tables[current]?[key] = value
            // prefix is everything up to and including the whitespace after "=", so the value can be swapped in place
            let leading = afterEq.prefix { $0 == " " || $0 == "\t" }
            let prefix = String(line[...eq]) + leading
            result.append(.keyValue(table: current, key: key, value: value, prefix: prefix, raw: valueText, suffix: suffix))
        }
        lines = result
        self.tables = tables
    }

    private static func isBareKey(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Returns (value, text of the value token, remainder such as a trailing comment).
    private static func parseValue(_ text: String, line: Int) throws -> (Value, String, String) {
        let stripped = text.trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { throw ParseError(line: line, message: "missing value after =") }
        let start = text.firstIndex { $0 != " " && $0 != "\t" }!
        let body = text[start...]

        if body.hasPrefix("\"\"\"") || body.hasPrefix("'''") {
            throw ParseError(line: line, message: "multi-line strings are not supported")
        }
        if body.hasPrefix("[") { throw ParseError(line: line, message: "arrays are not supported") }
        if body.hasPrefix("{") { throw ParseError(line: line, message: "inline tables are not supported") }

        if body.hasPrefix("\"") {
            var out = ""
            var i = body.index(after: body.startIndex)
            var closed = false
            while i < body.endIndex {
                let c = body[i]
                if c == "\"" { closed = true; i = body.index(after: i); break }
                if c == "\\" {
                    i = body.index(after: i)
                    guard i < body.endIndex else { break }
                    switch body[i] {
                    case "n": out += "\n"
                    case "t": out += "\t"
                    case "r": out += "\r"
                    case "b": out += "\u{08}"
                    case "f": out += "\u{0C}"
                    case "\"": out += "\""
                    case "\\": out += "\\"
                    case "u", "U":
                        let count = body[i] == "u" ? 4 : 8
                        let hexStart = body.index(after: i)
                        guard let hexEnd = body.index(hexStart, offsetBy: count, limitedBy: body.endIndex),
                              let code = UInt32(body[hexStart..<hexEnd], radix: 16), let scalar = Unicode.Scalar(code) else {
                            throw ParseError(line: line, message: "bad unicode escape in string")
                        }
                        out.unicodeScalars.append(scalar)
                        i = body.index(before: hexEnd)
                    default:
                        throw ParseError(line: line, message: "unknown escape \\\(body[i]) in string")
                    }
                    i = body.index(after: i)
                    continue
                }
                out.append(c)
                i = body.index(after: i)
            }
            guard closed else { throw ParseError(line: line, message: "string is missing its closing quote") }
            let rest = String(body[i...])
            try checkTrailing(rest, line: line)
            return (.string(out), String(body[..<i]), rest)
        }

        if body.hasPrefix("'") {
            let inner = body.dropFirst()
            guard let close = inner.firstIndex(of: "'") else {
                throw ParseError(line: line, message: "string is missing its closing quote")
            }
            let rest = String(inner[inner.index(after: close)...])
            try checkTrailing(rest, line: line)
            return (.string(String(inner[..<close])), String(body[...close]), rest)
        }

        // Bare token: up to whitespace or a comment.
        let tokenEnd = body.firstIndex { $0 == " " || $0 == "\t" || $0 == "#" } ?? body.endIndex
        let token = String(body[..<tokenEnd])
        let rest = String(body[tokenEnd...])
        try checkTrailing(rest, line: line)

        switch token {
        case "true": return (.bool(true), token, rest)
        case "false": return (.bool(false), token, rest)
        case "inf", "+inf": return (.float(.infinity), token, rest)
        case "-inf": return (.float(-.infinity), token, rest)
        case "nan", "+nan", "-nan": return (.float(.nan), token, rest)
        default: break
        }
        let plain = token.replacingOccurrences(of: "_", with: "")
        if let i = Int(plain), !token.contains(".") && !token.lowercased().contains("e") {
            return (.int(i), token, rest)
        }
        if token.contains("-") && token.first != "-" || token.contains(":") {
            throw ParseError(line: line, message: "dates and times are not supported")
        }
        if let d = Double(plain), plain.first.map({ $0.isNumber || $0 == "-" || $0 == "+" || $0 == "." }) ?? false {
            return (.float(d), token, rest)
        }
        throw ParseError(line: line, message: "cannot read value \"\(token)\" (strings need quotes)")
    }

    private static func checkTrailing(_ rest: String, line: Int) throws {
        let t = rest.trimmingCharacters(in: .whitespaces)
        guard t.isEmpty || t.hasPrefix("#") else {
            throw ParseError(line: line, message: "unexpected text after value: \(t)")
        }
    }

    // MARK: Reading

    func value(table: String, key: String) -> Value? {
        tables[table]?[key]
    }

    // MARK: Writing

    /// Sets a value, patching the existing line in place or appending the key
    /// to its table (creating the table at the end if needed).
    mutating func set(table: String, key: String, value: Value) {
        if let index = lines.firstIndex(where: {
            if case .keyValue(let t, let k, _, _, _, _) = $0 { return t == table && k == key } else { return false }
        }) {
            if case .keyValue(let t, let k, let old, let prefix, _, let suffix) = lines[index], old != value {
                lines[index] = .keyValue(table: t, key: k, value: value, prefix: prefix, raw: value.serialized, suffix: suffix)
            }
            tables[table, default: [:]][key] = value
            return
        }

        let newLine = Line.keyValue(table: table, key: key, value: value, prefix: "\(key) = ", raw: value.serialized, suffix: "")
        tables[table, default: [:]][key] = value

        if table.isEmpty {
            // Root keys go before the first table header, after any leading comment block.
            var insertAt = lines.firstIndex { if case .table = $0 { return true } else { return false } } ?? lines.count
            // Skip back over blank lines so the key sits with the root block.
            while insertAt > 0, case .verbatim(let text) = lines[insertAt - 1], text.trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            lines.insert(newLine, at: insertAt)
            return
        }

        if let header = lines.firstIndex(where: { if case .table(let n, _) = $0 { return n == table } else { return false } }) {
            // Insert after the section's last key; comments after that are taken to belong to what follows.
            var end = header + 1
            var lastContent = header
            while end < lines.count {
                if case .table = lines[end] { break }
                if case .keyValue = lines[end] { lastContent = end }
                end += 1
            }
            lines.insert(newLine, at: lastContent + 1)
            return
        }

        if let last = lines.last, case .verbatim(let text) = last, text.trimmingCharacters(in: .whitespaces).isEmpty {
            // already ends with a blank line
        } else if !lines.isEmpty {
            lines.append(.verbatim(""))
        }
        lines.append(.table(name: table, text: "[\(table)]"))
        lines.append(newLine)
    }

    var text: String {
        var out: [String] = []
        for line in lines {
            switch line {
            case .verbatim(let s): out.append(s)
            case .table(_, let s): out.append(s)
            case .keyValue(_, _, _, let prefix, let raw, let suffix): out.append(prefix + raw + suffix)
            }
        }
        return out.joined(separator: newline) + (out.isEmpty || !endsWithNewline ? "" : newline)
    }
}
