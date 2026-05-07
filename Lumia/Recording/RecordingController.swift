import Foundation
import CoreGraphics
import CoreVideo
import AppKit

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

        cameraCapture.onAudioBuffer = { [weak self] buffer in
            self?.movieWriter?.appendAudioBuffer(buffer)
        }
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
        cameraCapture.onAudioBuffer = nil
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
            let w = CVPixelBufferGetWidth(screen)
            let h = CVPixelBufferGetHeight(screen)
            screenSize = CGSize(width: w, height: h)
            movieWriter?.startWriting(width: w, height: h)
        }
        guard state.isRecording else { return }

        let webcam = cameraCapture.currentFrame()
        if let composited = FrameCompositor.composite(
            screen: screen, webcam: webcam,
            overlayFraction: state.overlayFraction,
            webcamZoom: state.webcamZoom,
            overlayPosition: state.overlayPosition
        ) {
            movieWriter?.appendFrame(composited)
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
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Lumia")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }
}
