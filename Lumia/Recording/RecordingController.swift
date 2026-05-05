import Foundation
import CoreGraphics
import CoreVideo

@MainActor
final class RecordingController {
    private let state: RecordingState
    private let screenCapture = ScreenCapture()
    private let cameraCapture: CameraCapture
    private var movieWriter: MovieWriter?
    private var screenSize: CGSize = .zero
    private var timer: Timer?

    init(state: RecordingState, cameraCapture: CameraCapture) {
        self.state = state
        self.cameraCapture = cameraCapture
    }

    func startRecording() async throws {
        let url = desktopURL()
        movieWriter = try MovieWriter(outputURL: url)

        try cameraCapture.start()

        screenCapture.onFrame = { [weak self] pixelBuffer, size in
            self?.handleScreenFrame(pixelBuffer, size: size)
        }
        try await screenCapture.start()

        state.startRecording()
        startTimer()
    }

    func pauseRecording() {
        state.pauseRecording()
        timer?.invalidate()
    }

    func resumeRecording() {
        state.resumeRecording()
        startTimer()
    }

    func stopRecording() async throws {
        timer?.invalidate()
        timer = nil
        try await screenCapture.stop()
        cameraCapture.stop()

        await withCheckedContinuation { continuation in
            movieWriter?.finish { _ in continuation.resume() }
        }
        state.stopRecording()
        screenSize = .zero
        movieWriter = nil
    }

    // MARK: - Private

    private func handleScreenFrame(_ screen: CVPixelBuffer, size: CGSize) {
        if screenSize == .zero {
            screenSize = size
            movieWriter?.startWriting(width: Int(size.width), height: Int(size.height))
        }
        guard state.isRecording else { return }

        let overlayRect = resolvedOverlayRect(screenSize: size)
        let webcam = cameraCapture.currentFrame()
        if let composited = FrameCompositor.composite(screen: screen, webcam: webcam, overlayRect: overlayRect) {
            movieWriter?.appendFrame(composited)
        }
    }

    private func resolvedOverlayRect(screenSize: CGSize) -> CGRect {
        let w: CGFloat = 280, h: CGFloat = 158, margin: CGFloat = 24
        switch state.overlayPosition {
        case .bottomRight:
            return CGRect(x: screenSize.width - w - margin,
                          y: screenSize.height - h - margin, width: w, height: h)
        case .bottomLeft:
            return CGRect(x: margin, y: screenSize.height - h - margin, width: w, height: h)
        case .custom(let point):
            return CGRect(origin: point, size: CGSize(width: w, height: h))
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.tick()
            }
        }
    }

    private func desktopURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "Lumia_\(formatter.string(from: Date())).mp4"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(name)
    }
}
