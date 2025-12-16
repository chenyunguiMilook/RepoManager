import SwiftUI
import AppKit
import Carbon.HIToolbox

/// 快捷键记录和修改视图
struct HotKeyRecorder: NSViewControllerRepresentable {
    @ObservedObject var settings: HotKeySettings
    var isRecording: Bool
    var onRecordingChange: (Bool) -> Void
    
    func makeNSViewController(context: Context) -> HotKeyRecorderViewController {
        let controller = HotKeyRecorderViewController()
        controller.settings = settings
        controller.isRecording = isRecording
        controller.onRecordingChange = onRecordingChange
        return controller
    }
    
    func updateNSViewController(_ nsViewController: HotKeyRecorderViewController, context: Context) {
        nsViewController.settings = settings
        nsViewController.isRecording = isRecording
    }
}

class HotKeyRecorderViewController: NSViewController {
    weak var settings: HotKeySettings?
    var isRecording: Bool = false
    var onRecordingChange: ((Bool) -> Void)?
    
    private var recordedKeyCode: UInt32 = 0
    private var recordedModifiers: UInt32 = 0
    private var eventMonitor: Any?
    
    override func loadView() {
        self.view = NSView()
    }
    
    func startRecording() {
        recordedKeyCode = 0
        recordedModifiers = 0
        
        // 开始监听全局按键
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // 消费该事件
        }
    }
    
    func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // 如果记录了按键，更新设置
        if recordedKeyCode > 0 {
            settings?.keyCode = recordedKeyCode
            settings?.modifiers = recordedModifiers
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        recordedKeyCode = UInt32(event.keyCode)
        recordedModifiers = UInt32(event.modifierFlags.rawValue) & UInt32((cmdKey | optionKey | controlKey | shiftKey))
        
        // 停止录制
        stopRecording()
        onRecordingChange?(false)
    }
}

/// SwiftUI 快捷键设置视图
struct HotKeySettingsView: View {
    @ObservedObject var settings: HotKeySettings
    @State private var isRecording = false
    @State private var showResetConfirm = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Text("全局快捷键:")
                    .frame(width: 80, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        // 显示当前快捷键
                        Text(settings.displayString)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 24)
                            .frame(minWidth: 120)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                            .border(Color.gray.opacity(0.3), width: 1)
                        
                        // 记录按钮
                        Button(action: toggleRecording) {
                            Text(isRecording ? "停止" : "更改...")
                                .frame(minWidth: 60)
                        }
                        .buttonStyle(.bordered)
                        
                        // 重置按钮
                        Button(action: { showResetConfirm = true }) {
                            Text("重置")
                                .frame(minWidth: 60)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text(isRecording ? "请按下要设置的快捷键组合" : "用于快速打开应用窗口")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Spacer()
        }
        .alert("重置快捷键", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) { }
            Button("重置为默认", role: .destructive) {
                settings.reset()
                AppDelegate.shared?.hotKeyManager.reregister(with: settings)
            }
        } message: {
            Text("快捷键将被重置为 F5")
        }
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }
    
    private func startRecording() {
        // 使用事件监听来捕获按键
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = Int(event.modifierFlags.rawValue) & (cmdKey | optionKey | controlKey | shiftKey)
            
            self.settings.keyCode = keyCode
            self.settings.modifiers = UInt32(modifiers)
            self.isRecording = false
            
            // 重新注册快捷键
            AppDelegate.shared?.hotKeyManager.reregister(with: settings)
            
            return nil
        }
    }
    
    private func stopRecording() {
        // 事件监听会自动停止
    }
}
