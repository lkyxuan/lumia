import ScreenCaptureKit
import CoreVideo

@MainActor
final class ScreenCapture: NSObject {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.lumia.screen", qos: .userInteractive)

    var onFrame: ((CVPixelBuffer, CGSize) -> Void)?

    func requestPermission() async -> Bool {
        do {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noScreen }

        // Exclude Lumia's own windows (control bar + webcam overlay) from the recording
        let excluded = content.applications.filter { $0.bundleIdentifier == "com.lumia.app" }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        try await stream?.stopCapture()
        stream = nil
    }
}

extension ScreenCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let size = CGSize(width: width, height: height)
        Task { @MainActor [weak self] in
            self?.onFrame?(buffer, size)
        }
    }
}
