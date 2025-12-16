import Foundation
import SwiftUI
import Combine
import Carbon.HIToolbox

/// 全局快捷键设置管理
@MainActor
final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()
    
    private static let keyCodeKey = "HotKeySettings.keyCode"
    private static let modifiersKey = "HotKeySettings.modifiers"
    
    // 默认快捷键：F5
    static let defaultKeyCode: UInt32 = 96
    static let defaultModifiers: UInt32 = 0
    
    @Published var keyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(keyCode, forKey: Self.keyCodeKey)
            notifyChange()
        }
    }
    
    @Published var modifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(modifiers, forKey: Self.modifiersKey)
            notifyChange()
        }
    }
    
    private init() {
        self.keyCode = UInt32(UserDefaults.standard.integer(forKey: Self.keyCodeKey))
        self.modifiers = UInt32(UserDefaults.standard.integer(forKey: Self.modifiersKey))
        if self.keyCode == 0 { self.keyCode = Self.defaultKeyCode }
    }
    
    func reset() {
        keyCode = Self.defaultKeyCode
        modifiers = Self.defaultModifiers
    }
    
    private func notifyChange() {
        NotificationCenter.default.post(name: NSNotification.Name("HotKeySettingsDidChange"), object: nil)
    }
    
    /// 返回可读的快捷键描述
    var displayString: String {
        let keyName = keyCodeToName(keyCode)
        let modifierNames = modifiersToNames(modifiers)
        
        if modifierNames.isEmpty {
            return keyName
        } else {
            return modifierNames.joined(separator: " + ") + " + " + keyName
        }
    }
    
    private func keyCodeToName(_ code: UInt32) -> String {
        // 常见的键盘按键映射
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 32: return "O"
        case 34: return "I"
        case 37: return "K"
        case 38: return "J"
        case 40: return ";"
        case 41: return ","
        case 43: return "/"
        case 44: return "N"
        case 45: return "M"
        case 47: return "."
        case 50: return "`"
        case 65: return "."
        case 67: return "*"
        case 69: return "+"
        case 71: return "Clear"
        case 75: return "/"
        case 76: return "Enter"
        case 78: return "-"
        case 81: return "="
        case 82: return "0"
        case 83: return "1"
        case 84: return "2"
        case 85: return "3"
        case 86: return "4"
        case 87: return "5"
        case 88: return "6"
        case 89: return "7"
        case 91: return "8"
        case 92: return "9"
        case 36: return "Enter"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        case 55: return "Cmd"
        case 56: return "Shift"
        case 57: return "CapsLock"
        case 58: return "Option"
        case 59: return "Control"
        case 60: return "Shift Right"
        case 61: return "Option Right"
        case 62: return "Control Right"
        case 63: return "Fn"
        case 64: return "F17"
        case 65: return "Decimal"
        case 67: return "Multiply"
        case 69: return "Add"
        case 71: return "NumLock"
        case 75: return "Divide"
        case 76: return "Enter"
        case 78: return "Subtract"
        case 81: return "Equal"
        case 82: return "Numpad0"
        case 83: return "Numpad1"
        case 84: return "Numpad2"
        case 85: return "Numpad3"
        case 86: return "Numpad4"
        case 87: return "Numpad5"
        case 88: return "Numpad6"
        case 89: return "Numpad7"
        case 91: return "Numpad8"
        case 92: return "Numpad9"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "PageUp"
        case 117: return "Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PageDown"
        case 122: return "F1"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default: return "Key(\(code))"
        }
    }
    
    private func modifiersToNames(_ mods: UInt32) -> [String] {
        var names: [String] = []
        if (mods & UInt32(cmdKey)) != 0 {
            names.append("Cmd")
        }
        if (mods & UInt32(optionKey)) != 0 {
            names.append("Option")
        }
        if (mods & UInt32(controlKey)) != 0 {
            names.append("Ctrl")
        }
        if (mods & UInt32(shiftKey)) != 0 {
            names.append("Shift")
        }
        return names
    }
}
