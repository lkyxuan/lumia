import AVFoundation
import CoreVideo

final class CameraCapture: NSObject {
    private let session = AVCaptureSession()
    var captureSession: AVCaptureSession { session }
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let videoQueue = DispatchQueue(label: "com.lumia.camera", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.lumia.audio", qos: .userInteractive)
    private var _latestPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()

    var onAudioBuffer: ((CMSampleBuffer) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    private var smoothedAudioLevel: Float = 0

    override init() {
        super.init()
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
    }

    func start() throws {
        guard !session.isRunning else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw CaptureError.noCamera
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let micDevice = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: micDevice),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        session.commitConfiguration()
        session.startRunning()
    }

    static func availableCameras() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func availableMicrophones() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    func switchCamera(to device: AVCaptureDevice) {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.video) }
            .forEach { session.removeInput($0) }
        if session.canAddInput(newInput) { session.addInput(newInput) }
        session.commitConfiguration()
    }

    func switchMicrophone(to device: AVCaptureDevice) {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.audio) }
            .forEach { session.removeInput($0) }
        if session.canAddInput(newInput) { session.addInput(newInput) }
        session.commitConfiguration()
    }

    func stop() {
        session.stopRunning()
        lock.withLock { _latestPixelBuffer = nil }
    }

    func currentFrame() -> CVPixelBuffer? {
        lock.withLock { _latestPixelBuffer }
    }

    private func rms(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var length = 0
        var rawPtr: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &rawPtr) == kCMBlockBufferNoErr,
              let rawPtr else { return 0 }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bytesPerSample = max(1, Int(asbd.mBitsPerChannel) / 8)
        let count = length / bytesPerSample
        guard count > 0 else { return 0 }

        var sum: Float = 0
        if isFloat {
            let samples = UnsafeRawPointer(rawPtr).bindMemory(to: Float32.self, capacity: count)
            for i in 0..<count { sum += samples[i] * samples[i] }
        } else {
            let samples = UnsafeRawPointer(rawPtr).bindMemory(to: Int16.self, capacity: count)
            for i in 0..<count { let s = Float(samples[i]) / 32768.0; sum += s * s }
        }
        return sqrt(sum / Float(count))
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            onAudioBuffer?(sampleBuffer)
            let level = rms(from: sampleBuffer)
            smoothedAudioLevel = level > smoothedAudioLevel
                ? smoothedAudioLevel * 0.3 + level * 0.7
                : smoothedAudioLevel * 0.88 + level * 0.12
            let smoothed = smoothedAudioLevel
            DispatchQueue.main.async { [weak self] in self?.onAudioLevel?(smoothed) }
        } else {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lock.withLock { _latestPixelBuffer = buffer }
        }
    }
}

enum CaptureError: Error {
    case noCamera
    case noScreen
}
