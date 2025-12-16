import Foundation
import Carbon

/// Lightweight global hotkey wrapper using Carbon.
/// Works even when the app is not key, as long as the app process is running.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private let hotKeyID = EventHotKeyID(signature: OSType(0x4748544B), id: 1) // 'GHTK'

    var onHotKey: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var id = hotKeyID
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            print("RegisterEventHotKey failed: \(status)")
            return
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotKey?()
            return noErr
        }

        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        if handlerStatus != noErr {
            print("InstallEventHandler failed: \(handlerStatus)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
