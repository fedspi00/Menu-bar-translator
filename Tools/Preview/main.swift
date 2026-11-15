// Renders the panel to a PNG without needing screen-recording permission.
// Usage: preview <out.png> [text] [seconds]
import AppKit
import SwiftUI

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/panel.png"
let seed = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let wait = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) ?? 3.0 : 3.0

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if ProcessInfo.processInfo.environment["DARK"] != nil {
        app.appearance = NSAppearance(named: .darkAqua)
    }

    let store = Store()
    let loginItem = LoginItem()
    let view = ContentView(store: store, loginItem: loginItem)

    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 372)

    // Stand in for the popover's vibrant backdrop so the capture shows the
    // same contrast the real panel has.
    let backdrop = NSVisualEffectView(frame: hosting.frame)
    backdrop.material = .popover
    backdrop.state = .active
    backdrop.blendingMode = .behindWindow
    backdrop.autoresizingMask = [.width, .height]
    backdrop.addSubview(hosting)

    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = backdrop
    if ProcessInfo.processInfo.environment["DARK"] != nil {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
    } else {
        window.backgroundColor = .windowBackgroundColor
    }
    window.setFrameOrigin(NSPoint(x: 60, y: 60))
    window.orderFrontRegardless()

    if !seed.isEmpty { store.input = seed }

    RunLoop.current.run(until: Date().addingTimeInterval(wait))

    backdrop.layoutSubtreeIfNeeded()
    guard let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else {
        print("cannot make bitmap rep")
        exit(1)
    }
    backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("cannot encode png")
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)  output=\(store.output.prefix(80))  direction=\(String(describing: store.direction))")
    exit(0)
}
