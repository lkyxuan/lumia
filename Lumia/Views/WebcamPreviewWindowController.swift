import AppKit
import AVFoundation

final class WebcamPreviewWindowController: NSWindowController {
    private let state: RecordingState
    private let cameraCapture: CameraCapture
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(state: RecordingState, cameraCapture: CameraCapture) {
        self.state = state
        self.cameraCapture = cameraCapture

        let size: CGFloat = 200
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        super.init(window: panel)

        let contentView = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        contentView.onRightClick = { [weak self] in self?.showCameraMenu() }
        panel.contentView = contentView

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = size / 2
        contentView.layer?.masksToBounds = true

        let layer = AVCaptureVideoPreviewLayer(session: cameraCapture.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.cornerRadius = size / 2
        layer.masksToBounds = true
        contentView.layer?.addSublayer(layer)
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

    private func showCameraMenu() {
        let cameras = CameraCapture.availableCameras()
        guard !cameras.isEmpty else { return }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "选择摄像头", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        for device in cameras {
            let item = NSMenuItem(
                title: device.localizedName,
                action: #selector(selectCamera(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: .zero, in: window?.contentView)
    }

    @objc private func selectCamera(_ item: NSMenuItem) {
        guard let device = item.representedObject as? AVCaptureDevice else { return }
        cameraCapture.switchCamera(to: device)
    }

    @objc private func windowMoved() {
        guard let window, let screen = window.screen else { return }
        let scale = screen.backingScaleFactor
        let frame = window.frame
        let x = frame.minX * scale
        let y = (screen.frame.height - frame.maxY) * scale
        Task { @MainActor [weak self] in
            self?.state.overlayPosition = .custom(CGPoint(x: x, y: y))
        }
    }

    private func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 24
        let size: CGFloat = 200
        let x = screen.frame.maxX - size - margin
        let y = screen.frame.minY + margin
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class CameraPreviewView: NSView {
    var onRightClick: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}
