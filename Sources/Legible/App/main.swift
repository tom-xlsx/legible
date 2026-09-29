import AppKit

if CommandLine.arguments.contains("--version") {
    print(AppInfo.versionDescription)
    exit(0)
}

let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
