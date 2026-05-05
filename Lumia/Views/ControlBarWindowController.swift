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
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
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
            session: cameraCapture.captureSession
        )
        webcamWindow?.showWindow(nil)

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
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startRecording() async {
        do { try await controller?.startRecording() }
        catch { print("录制启动失败: \(error)") }
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
