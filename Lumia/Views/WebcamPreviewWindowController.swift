import AppKit
import AVFoundation

final class WebcamPreviewWindowController: NSWindowController {
    private let state: RecordingState
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(state: RecordingState, session: AVCaptureSession) {
        self.state = state

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 113),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "摄像头"
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .black

        super.init(window: panel)

        let previewView = NSView(frame: panel.contentView!.bounds)
        previewView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(previewView)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewView.bounds
        previewView.layer = layer
        previewView.wantsLayer = true
        previewLayer = layer

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        positionBottomRight()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func windowMoved() {
        guard let window, let screen = window.screen else { return }
        let frame = window.frame
        let x = frame.minX
        let y = screen.frame.height - frame.maxY
        Task { @MainActor [weak self] in
            self?.state.overlayPosition = .custom(CGPoint(x: x, y: y))
        }
    }

    private func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 24
        let w: CGFloat = 200, h: CGFloat = 113
        let x = screen.frame.maxX - w - margin
        let y = screen.frame.minY + margin
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
