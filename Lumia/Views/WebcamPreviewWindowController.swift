import AppKit
import AVFoundation

final class WebcamPreviewWindowController: NSWindowController {
    private let state: RecordingState
    private let cameraCapture: CameraCapture
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentPreviewSize: CGFloat = 200

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
        panel.isMovableByWindowBackground = false
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

        movePreviewWindow(to: state.overlayPosition)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Right-click menu

    private func showCameraMenu() {
        let menu = NSMenu()

        // Camera selection
        let cameraHeader = NSMenuItem(title: "选择摄像头", action: nil, keyEquivalent: "")
        cameraHeader.isEnabled = false
        menu.addItem(cameraHeader)
        menu.addItem(.separator())
        for device in CameraCapture.availableCameras() {
            let item = NSMenuItem(title: device.localizedName,
                                  action: #selector(selectCamera(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = device
            menu.addItem(item)
        }

        // Microphone selection
        menu.addItem(.separator())
        let micHeader = NSMenuItem(title: "选择麦克风", action: nil, keyEquivalent: "")
        micHeader.isEnabled = false
        menu.addItem(micHeader)
        menu.addItem(.separator())
        for device in CameraCapture.availableMicrophones() {
            let item = NSMenuItem(title: device.localizedName,
                                  action: #selector(selectMicrophone(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = device
            menu.addItem(item)
        }

        // Position
        menu.addItem(.separator())
        let posHeader = NSMenuItem(title: "位置", action: nil, keyEquivalent: "")
        posHeader.isEnabled = false
        menu.addItem(posHeader)
        for (label, pos) in [("左上角", OverlayPosition.topLeft),
                              ("右上角", .topRight),
                              ("左下角", .bottomLeft),
                              ("右下角", .bottomRight)] {
            let item = NSMenuItem(title: label, action: #selector(setPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pos as AnyObject
            item.state = state.overlayPosition == pos ? .on : .off
            menu.addItem(item)
        }

        // Circle size
        menu.addItem(.separator())
        let sizeHeader = NSMenuItem(title: "圆圈大小", action: nil, keyEquivalent: "")
        sizeHeader.isEnabled = false
        menu.addItem(sizeHeader)
        for (label, fraction) in [("大 (默认)", 0.20), ("超大", 0.24), ("特大", 0.28)] as [(String, CGFloat)] {
            let item = NSMenuItem(title: label, action: #selector(setOverlaySize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: Double(fraction))
            item.state = abs(state.overlayFraction - fraction) < 0.01 ? .on : .off
            menu.addItem(item)
        }

        // Webcam zoom
        menu.addItem(.separator())
        let zoomHeader = NSMenuItem(title: "画面缩放", action: nil, keyEquivalent: "")
        zoomHeader.isEnabled = false
        menu.addItem(zoomHeader)
        for (label, zoom) in [("1× (默认)", 1.0), ("1.2×", 1.2), ("1.5×", 1.5)] as [(String, CGFloat)] {
            let item = NSMenuItem(title: label, action: #selector(setWebcamZoom(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: Double(zoom))
            item.state = abs(state.webcamZoom - zoom) < 0.01 ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: .zero, in: window?.contentView)
    }

    @objc private func selectCamera(_ item: NSMenuItem) {
        guard let device = item.representedObject as? AVCaptureDevice else { return }
        cameraCapture.switchCamera(to: device)
    }

    @objc private func selectMicrophone(_ item: NSMenuItem) {
        guard let device = item.representedObject as? AVCaptureDevice else { return }
        cameraCapture.switchMicrophone(to: device)
    }

    @objc private func setPosition(_ item: NSMenuItem) {
        guard let pos = item.representedObject as? OverlayPosition else { return }
        state.overlayPosition = pos
        movePreviewWindow(to: pos)
    }

    @objc private func setOverlaySize(_ item: NSMenuItem) {
        guard let fraction = (item.representedObject as? NSNumber).map({ CGFloat($0.doubleValue) }) else { return }
        state.overlayFraction = fraction
        let newSize = (200.0 * fraction / 0.20).rounded()
        resizePreview(to: newSize)
        movePreviewWindow(to: state.overlayPosition)
    }

    @objc private func setWebcamZoom(_ item: NSMenuItem) {
        guard let zoom = (item.representedObject as? NSNumber).map({ CGFloat($0.doubleValue) }) else { return }
        state.webcamZoom = zoom
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.setAffineTransform(CGAffineTransform(scaleX: zoom, y: zoom))
        CATransaction.commit()
    }

    // MARK: - Helpers

    private func resizePreview(to newSize: CGFloat) {
        guard let contentView = window?.contentView else { return }
        currentPreviewSize = newSize

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.frame = NSRect(x: 0, y: 0, width: newSize, height: newSize)
        contentView.layer?.cornerRadius = newSize / 2
        previewLayer?.setAffineTransform(.identity)
        previewLayer?.frame = CGRect(x: 0, y: 0, width: newSize, height: newSize)
        previewLayer?.cornerRadius = newSize / 2
        let zoom = state.webcamZoom
        previewLayer?.setAffineTransform(CGAffineTransform(scaleX: zoom, y: zoom))
        CATransaction.commit()

        window?.setContentSize(NSSize(width: newSize, height: newSize))
    }

    private func movePreviewWindow(to position: OverlayPosition) {
        guard let screen = NSScreen.main else { return }
        let size = currentPreviewSize
        let margin: CGFloat = 24
        let f = screen.frame
        let origin: NSPoint
        switch position {
        case .bottomRight: origin = NSPoint(x: f.maxX - size - margin, y: f.minY + margin)
        case .bottomLeft:  origin = NSPoint(x: f.minX + margin,         y: f.minY + margin)
        case .topRight:    origin = NSPoint(x: f.maxX - size - margin, y: f.maxY - size - margin)
        case .topLeft:     origin = NSPoint(x: f.minX + margin,         y: f.maxY - size - margin)
        }
        window?.setFrameOrigin(origin)
    }
}

private final class CameraPreviewView: NSView {
    var onRightClick: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}
