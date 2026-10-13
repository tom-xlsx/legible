import Foundation

// App extensions have no main of their own: Foundation's NSExtensionMain runs the
// extension's XPC loop and instantiates NSExtensionPrincipalClass from Info.plist.
@_silgen_name("NSExtensionMain")
func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

exit(NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
