import Foundation
import Carbon
import Carbon.HIToolbox

@MainActor
enum InputSourceManager {
    /// Best-effort switch to an ASCII-capable (English) input source.
    /// Tries ABC first, then US, then any ASCII-capable source.
    static func switchToEnglish() {
        if let abc = findInputSource(inputSourceID: "com.apple.keylayout.ABC") {
            _ = TISSelectInputSource(abc)
            return
        }
        if let us = findInputSource(inputSourceID: "com.apple.keylayout.US") {
            _ = TISSelectInputSource(us)
            return
        }
        if let ascii = findFirstASCIICapableInputSource() {
            _ = TISSelectInputSource(ascii)
        }
    }

    private static func findInputSource(inputSourceID: String) -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil as CFDictionary?, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first(where: { source in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return id == inputSourceID
        })
    }

    private static func findFirstASCIICapableInputSource() -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil as CFDictionary?, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first(where: { source in
            guard let asciiPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
            let asciiCapable = Unmanaged<CFBoolean>.fromOpaque(asciiPtr).takeUnretainedValue()
            return CFBooleanGetValue(asciiCapable)
        })
    }
}
