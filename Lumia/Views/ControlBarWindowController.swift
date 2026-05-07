import AppKit
import SwiftUI
import AVFoundation

final class ControlBarWindowController: NSWindowController {
    private let state = RecordingState()
    private var controller: RecordingController?
    private var webcamWindow: WebcamPreviewWindowController?
    private let cameraCapture = CameraCapture()

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 272, height: 44),
            styleMask: [.titled, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        super.init(window: panel)

        controller = RecordingController(state: state, cameraCapture: cameraCapture)

        webcamWindow = WebcamPreviewWindowController(
            state: state,
            cameraCapture: cameraCapture
        )
        webcamWindow?.showWindow(nil)

        // Start camera immediately so preview is live from launch
        Task { [weak self] in try? self?.cameraCapture.start() }

        cameraCapture.onAudioLevel = { [weak self] level in
            self?.state.audioLevel = level
        }

        let view = ControlBarView(
            onStart: { [weak self] in
                Task { @MainActor [weak self] in await self?.startRecording() }
            },
            onPause: { [weak self] in
                Task { @MainActor [weak self] in self?.togglePause() }
            },
            onStop: { [weak self] in
                Task { @MainActor [weak self] in await self?.stopRecording() }
            }
        )
        .environment(state)

        panel.contentView = NSHostingView(rootView: view)
        panel.setFrameOrigin(topCenterOrigin())

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command, .shift] else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event.keyCode {
                case 15: // R key
                    if self.state.status == .idle {
                        await self.startRecording()
                    } else {
                        await self.stopRecording()
                    }
                case 35: // P key
                    self.togglePause()
                default:
                    break
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startRecording() async {
        do { try await controller?.startRecording() }
        catch {
            let alert = NSAlert()
            if (error as NSError).code == -3801 {
                alert.messageText = "需要屏幕录制权限"
                alert.informativeText = "请前往「系统设置 → 隐私与安全性 → 录屏与系统录音」，开启 Lumia 的权限，然后完全退出并重新打开 Lumia。"
                alert.addButton(withTitle: "退出 Lumia")
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "取消")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSApp.terminate(nil)
                } else if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            } else {
                alert.messageText = "录制启动失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func togglePause() {
        if state.status == .recording { controller?.pauseRecording() }
        else if state.status == .paused { controller?.resumeRecording() }
    }

    private func stopRecording() async {
        do { try await controller?.stopRecording() }
        catch { print("录制停止失败: \(error)") }
    }

    private func topCenterOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let x = (screen.frame.width - 240) / 2
        let y = screen.frame.maxY - 70
        return NSPoint(x: x, y: y)
    }
}
