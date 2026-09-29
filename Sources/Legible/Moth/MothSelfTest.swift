import AppKit

/// `Legible --moth-selftest=fixtures/kitchen-sink.md`
/// Perch selection across every theme at three window widths, the droppings
/// cap, the nibble rate over many seeded runs, and inertness while held.
final class MothSelfTestJob {
    private let input: URL
    private var failures: [String] = []
    private let widths: [CGFloat] = [700, 1000, 1400]

    init?(options: LaunchOptions) {
        guard let input = options.mothSelfTestInput else { return nil }
        self.input = URL(fileURLWithPath: input)
    }

    func run() {
        MothController.forceEnabled = true
        MothController.seedOverride = 7
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.finish(fatal: "timed out") }
        NSDocumentController.shared.openDocument(withContentsOf: input, display: true) { [self] document, _, error in
            guard let document = document as? MarkdownDocument, let controller = document.viewController,
                  let window = controller.view.window as? DocumentWindow else {
                finish(fatal: "cannot open \(input.path): \(error?.localizedDescription ?? "unknown error")")
            }
            window.allowsOversize = true
            let proceed = { [self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.runPerchChecks(controller, window: window, themes: ThemeManager.shared.themes, index: 0) }
            }
            if controller.hasRendered { proceed() } else { controller.onRendered = { _ in proceed() } }
        }
    }

    private func runPerchChecks(_ controller: DocumentViewController, window: DocumentWindow, themes: [Theme], index: Int) {
        guard index < themes.count * widths.count else { runBehaviourChecks(controller); return }
        let theme = themes[index / widths.count]
        let width = widths[index % widths.count]
        ThemeManager.shared.selectedID = theme.id
        window.setContentSize(NSSize(width: width, height: 800))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [self] in
            controller.preview.evaluate("LegibleMoth.test.checkPerches()") { [self] result in
                let dict = result as? [String: Any] ?? [:]
                let label = "\(theme.name) @ \(Int(width))px"
                if let error = dict["error"] as? String { self.failures.append("\(label): \(error)") }
                let clear = dict["clear"] as? Int ?? 0
                let offenders = dict["offenders"] as? [[String: Any]] ?? []
                if !offenders.isEmpty { self.failures.append("\(label): \(offenders.count) perch(es) overlap text: \(offenders.prefix(3))") }
                if clear == 0 && width >= 1000 { self.failures.append("\(label): no clear perch found") }
                if (dict["detectorRejectsText"] as? Bool) != true { self.failures.append("\(label): overlap detector accepted a perch on a paragraph") }
                if (dict["textRects"] as? Int ?? 0) < 100 { self.failures.append("\(label): only \(dict["textRects"] ?? 0) text rects measured") }
                print("perches \(label): \(dict["candidates"] ?? 0) candidates, \(clear) clear, \(offenders.count) overlapping")
                self.runPerchChecks(controller, window: window, themes: themes, index: index + 1)
            }
        }
    }

    private func runBehaviourChecks(_ controller: DocumentViewController) {
        let preview = controller.preview
        preview.evaluate("LegibleMoth.test.droppingsCap()") { [self] result in
            let d = result as? [String: Any] ?? [:]
            let n = d["afterTenBatches"] as? Int ?? -1
            if n != 6 { failures.append("droppings after ten idle batches: \(n), expected the cap of 6") }
            if (d["whileHousetrained"] as? Int ?? -1) != 0 { failures.append("housetrained moth left droppings") }
            preview.evaluate("LegibleMoth.test.nibbleRate(20000)") { [self] result in
                let r = (result as? [String: Any])?["rate"] as? Double ?? -1
                if !(0.007...0.013).contains(r) { failures.append("nibble rate over 20000 seeded runs was \(r), expected about 0.01") }
                print("nibble rate: \(r)")
                // Held: everything must go.
                MothController.forceEnabled = false
                controller.applySettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                    preview.evaluate("document.querySelectorAll('.moth, .moth-mark, .moth-evidence').length + ':' + LegibleMoth.status().state") { [self] result in
                        let s = result as? String ?? "?"
                        if s != "0:held" { failures.append("while held the page still has moth elements or state (\(s))") }
                        finish(fatal: nil)
                    }
                }
            }
        }
    }

    private func finish(fatal: String?) -> Never {
        if let fatal { failures.append(fatal) }
        if failures.isEmpty { print("moth selftest: PASS"); exit(0) }
        for f in failures { print("moth selftest: FAIL  \(f)") }
        exit(1)
    }
}

#if DEBUG
/// Debug builds only: force any state or event, and speed up time.
enum MothDebugMenu {
    static func build() -> NSMenuItem {
        let menu = NSMenu(title: "Moth")
        let poses = NSMenu(title: "Force Pose")
        for pose in MothPack.requiredPoses { poses.item(pose, #selector(MothDebugTarget.forcePose(_:)), target: MothDebugTarget.shared) }
        menu.item("Force Pose", nil).submenu = poses
        let events = NSMenu(title: "Send Event")
        for event in ["copy", "find-open", "find-close", "reload", "editor-open", "editor-close", "external-link", "selection", "poke"] {
            events.item(event, #selector(MothDebugTarget.sendEvent(_:)), target: MothDebugTarget.shared)
        }
        menu.item("Send Event", nil).submenu = events
        menu.addItem(.separator())
        for (title, call) in [("Arrive Now", "arrive"), ("Relocate Now", "relocate"), ("Doze Now", "doze"), ("Leave Droppings", "droppings"), ("Show Nibble", "nibble")] {
            let item = menu.item(title, #selector(MothDebugTarget.call(_:)), target: MothDebugTarget.shared)
            item.representedObject = call
        }
        menu.addItem(.separator())
        let time = NSMenu(title: "Time")
        for scale in [1, 10, 60] {
            let item = time.item("×\(scale)", #selector(MothDebugTarget.timeScale(_:)), target: MothDebugTarget.shared)
            item.tag = scale
        }
        menu.item("Time", nil).submenu = time
        menu.item("Log Status", #selector(MothDebugTarget.status(_:)), target: MothDebugTarget.shared)
        let top = NSMenuItem(title: "Moth", action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }
}

final class MothDebugTarget: NSObject {
    static let shared = MothDebugTarget()

    private var preview: PreviewView? {
        (NSApp.keyWindow?.windowController as? DocumentWindowController)?.viewController.preview
    }

    @objc func forcePose(_ sender: NSMenuItem) { preview?.evaluate("LegibleMoth.debug.force('\(sender.title)')") { _ in } }
    @objc func sendEvent(_ sender: NSMenuItem) { preview?.evaluate("LegibleMoth.debug.event('\(sender.title)', {x: window.scrollX + 200, y: window.scrollY + 200})") { _ in } }
    @objc func call(_ sender: NSMenuItem) { preview?.evaluate("LegibleMoth.debug.\(sender.representedObject as? String ?? "status")()") { _ in } }
    @objc func timeScale(_ sender: NSMenuItem) {
        MothController.timeScale = Double(sender.tag)
        preview?.evaluate("LegibleMoth.debug.timeScale(\(sender.tag))") { _ in }
    }
    @objc func status(_ sender: NSMenuItem) {
        preview?.evaluate("JSON.stringify(LegibleMoth.status())") { result in NSLog("Moth: %@", result as? String ?? "nil") }
    }
}
#endif
