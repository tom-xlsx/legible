import Foundation
import UniformTypeIdentifiers
import WebKit

/// legible-asset://app/…  → files inside the app bundle's web/ folder.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "legible-asset"
    static let indexURL = URL(string: "\(scheme)://app/index.html")!

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let path = url.path.isEmpty ? "/index.html" : url.path
        let root = AppInfo.webRoot
        guard let file = SchemeFileServer.contained(root.appendingPathComponent(path), within: root) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        SchemeFileServer.serve(file, to: task)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// legible-doc://<token>/…  → files next to the open document (bounded by DocumentRegistry).
final class DocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "legible-doc"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let token = url.host,
              let file = DocumentRegistry.shared.resolve(token: token, path: url.path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        SchemeFileServer.serve(file, to: task)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

enum SchemeFileServer {
    /// Returns the resolved file URL if it lives inside `root`, otherwise nil.
    static func contained(_ file: URL, within root: URL) -> URL? {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    static func serve(_ file: URL, to task: WKURLSchemeTask) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let data = try? Data(contentsOf: file), let url = task.request.url else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mimeType(for: file),
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        default:
            return UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
