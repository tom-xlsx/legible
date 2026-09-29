import AppKit
import UniformTypeIdentifiers

/// Makes Legible the default handler for Markdown files (the system confirms).
enum DefaultApp {
    static let markdownType = UTType("net.daringfireball.markdown") ?? .plainText

    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: markdownType) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault(completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdownType) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    static func makeDefaultFromMenu(_ sender: Any?) {
        makeDefault { error in
            if let error {
                NSApp.presentError(error)
            }
        }
    }
}

/// Menu target for the default-app action (menus need an object target).
final class DefaultAppMenuTarget: NSObject {
    static let shared = DefaultAppMenuTarget()

    @objc func makeDefault(_ sender: Any?) {
        DefaultApp.makeDefaultFromMenu(sender)
    }
}
