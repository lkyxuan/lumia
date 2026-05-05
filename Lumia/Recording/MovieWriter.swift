import AVFoundation
import CoreVideo

final class MovieWriter {
    private let writer: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var frameCount: Int64 = 0
    private let frameRate: Int32 = 30
    private var hasStarted = false

    init(outputURL: URL) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    }

    func startWriting(width: Int, height: Int) {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        writer.add(input)
        videoInput = input
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        hasStarted = true
    }

    func appendFrame(_ pixelBuffer: CVPixelBuffer) {
        guard hasStarted, let input = videoInput, input.isReadyForMoreMediaData else { return }
        let time = CMTime(value: frameCount, timescale: frameRate)
        adaptor?.append(pixelBuffer, withPresentationTime: time)
        frameCount += 1
    }

    func finish(completion: @escaping (URL?) -> Void) {
        guard hasStarted else {
            completion(nil)
            return
        }
        videoInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { completion(nil); return }
            let url = self.writer.status == .completed ? self.writer.outputURL : nil
            completion(url)
        }
    }
}
