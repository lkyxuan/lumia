import AVFoundation
import CoreVideo

final class CameraCapture: NSObject {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.lumia.camera", qos: .userInteractive)
    private var _latestPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()

    override init() {
        super.init()
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    }

    func start() throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw CaptureError.noCamera
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
        lock.withLock { _latestPixelBuffer = nil }
    }

    func currentFrame() -> CVPixelBuffer? {
        lock.withLock { _latestPixelBuffer }
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.withLock { _latestPixelBuffer = buffer }
    }
}

enum CaptureError: Error {
    case noCamera
    case noScreen
}
