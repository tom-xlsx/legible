import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchOptions = LaunchOptions(arguments: CommandLine.arguments)
    private var snapshotJob: SnapshotJob?
    private var selfTestJob: SelfTestJob?
    private var settingsSnapshotJob: SettingsSnapshotJob?
    private var garnishSnapshotJob: GarnishSnapshotJob?
    private var mothSheetJob: MothSheetJob?
    private var quickLookJob: QuickLookSnapshotJob?
    private var mothSelfTestJob: MothSelfTestJob?
    private var restoredSession = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if launchOptions.isHeadless {
            NSApp.setActivationPolicy(.accessory)   // snapshots and self-tests must not steal focus from whatever is being typed
        }
        NSWindow.allowsAutomaticWindowTabbing = false
        ThemeManager.shared.start()
        SettingsStore.shared.start()
        SettingsApplier.shared.start()
        NSApp.mainMenu = MainMenu.build()
        DockIconController.shared.start()
    }

    @objc func newFromClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        do { _ = try MarkdownDocument.makeUntitled(text: text, opensWithEditor: false) } catch { NSApp.presentError(error) }
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if launchOptions.printDocuments {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let names = NSDocumentController.shared.documents.compactMap { $0.fileURL?.lastPathComponent }
                print("documents: \(names.isEmpty ? "(none)" : names.joined(separator: ", "))")
                exit(0)
            }
            return
        }
        if let job = SnapshotJob(options: launchOptions) {
            snapshotJob = job
            job.run()
        } else if let job = SelfTestJob(options: launchOptions) {
            selfTestJob = job
            job.run()
        } else if let job = SettingsSnapshotJob(options: launchOptions) {
            settingsSnapshotJob = job
            job.run()
        } else if let job = QuickLookSnapshotJob(options: launchOptions) {
            quickLookJob = job
            job.run()
        } else if let job = GarnishSnapshotJob(options: launchOptions) {
            garnishSnapshotJob = job
            job.run()
        } else if let job = MothSheetJob(options: launchOptions) {
            mothSheetJob = job
            job.run()
        } else if let job = MothSelfTestJob(options: launchOptions) {
            mothSelfTestJob = job
            job.run()
        }
    }

    // Snapshot the open documents before AppKit starts closing them, then let
    // the document controller run its usual unsaved-changes review.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Session.record()
        MothBookmarks.shared.save()
        NSDocumentController.shared.reviewUnsavedDocuments(
            withAlertTitle: nil, cancellable: true, delegate: self,
            didReviewAllSelector: #selector(documentController(_:didReviewAll:contextInfo:)), contextInfo: nil)
        return .terminateLater
    }

    @objc private func documentController(_ controller: NSDocumentController, didReviewAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        NSApp.reply(toApplicationShouldTerminate: didReviewAll)
    }

    // Launched with nothing to show (or Dock icon clicked with no windows): offer the open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !launchOptions.isHeadless
    }

    // AppKit calls this only when the app was launched with nothing to open (and
    // when the Dock icon is clicked with no windows). At launch, bring back the
    // last session; otherwise offer the open panel.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if !restoredSession {
            restoredSession = true
            if Session.restore() { return true }
        }
        if launchOptions.printDocuments { return true }
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: AppInfo.versionDescription,
            .version: "",
            .credits: Garnish.aboutCredits(),
        ])
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(newFromClipboard(_:)) {
            return NSPasteboard.general.string(forType: .string)?.isEmpty == false
        }
        return true
    }
}
