import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Uses the Carbon hot key API, which is the
/// only way to grab a shortcut globally without asking for Accessibility
/// permission.
final class HotKey {

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private let id: UInt32
    private var reference: EventHotKeyRef?

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_T`.
    ///   - modifiers: Carbon modifier mask, e.g. `cmdKey | optionKey`.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.installEventHandlerIfNeeded()

        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D42_5452), id: id) // 'MBTR'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, reference != nil else {
            HotKey.handlers[id] = nil
            return nil
        }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        HotKey.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard status == noErr else { return status }
                if let action = HotKey.handlers[pressed.id] {
                    DispatchQueue.main.async(execute: action)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }
}
