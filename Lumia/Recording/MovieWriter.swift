import AVFoundation
import CoreVideo

final class MovieWriter {
    private let writer: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStartTime: CMTime = .invalid
    private var hasStarted = false

    init(outputURL: URL) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    }

    func startWriting(width: Int, height: Int) {
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: nil
        )
        writer.add(vInput)
        videoInput = vInput

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        if writer.canAdd(aInput) {
            writer.add(aInput)
            audioInput = aInput
        }

        writer.startWriting()
        hasStarted = true
    }

    func appendFrame(_ pixelBuffer: CVPixelBuffer) {
        guard hasStarted, let input = videoInput, input.isReadyForMoreMediaData else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        if sessionStartTime == .invalid {
            sessionStartTime = now
            writer.startSession(atSourceTime: now)
        }
        adaptor?.append(pixelBuffer, withPresentationTime: now)
    }

    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard hasStarted, sessionStartTime != .invalid,
              let input = audioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func finish(completion: @escaping (URL?) -> Void) {
        guard hasStarted else {
            completion(nil)
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { completion(nil); return }
            let url = self.writer.status == .completed ? self.writer.outputURL : nil
            completion(url)
        }
    }
}
