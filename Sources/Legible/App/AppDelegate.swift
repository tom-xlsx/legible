import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchOptions = LaunchOptions(arguments: CommandLine.arguments)
    private var snapshotJob: SnapshotJob?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        ThemeManager.shared.start()
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let job = SnapshotJob(options: launchOptions) {
            snapshotJob = job
            job.run()
        }
    }

    // Launched with nothing to show (or Dock icon clicked with no windows): offer the open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !launchOptions.isHeadless
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: AppInfo.versionDescription,
            .version: "",
        ])
    }
}
