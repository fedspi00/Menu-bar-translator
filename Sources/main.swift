import AppKit

/// NSApplication holds its delegate weakly, so keep a strong reference here.
var retainedDelegate: AppDelegate?

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
