import XCTest
import CoreVideo
@testable import Lumia

final class FrameCompositorTests: XCTestCase {
    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer!
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer
    }

    func test_composite_returnsBufferWithCorrectDimensions() {
        let screen = makePixelBuffer(width: 1920, height: 1080)
        let webcam = makePixelBuffer(width: 640, height: 360)
        let rect = CGRect(x: 1600, y: 20, width: 280, height: 158)

        let result = FrameCompositor.composite(screen: screen, webcam: webcam, overlayRect: rect)

        XCTAssertNotNil(result)
        XCTAssertEqual(CVPixelBufferGetWidth(result!), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(result!), 1080)
    }

    func test_composite_withoutWebcam_returnsOutputBuffer() {
        let screen = makePixelBuffer(width: 1920, height: 1080)
        let rect = CGRect(x: 1600, y: 20, width: 280, height: 158)

        let result = FrameCompositor.composite(screen: screen, webcam: nil, overlayRect: rect)

        XCTAssertNotNil(result)
        XCTAssertEqual(CVPixelBufferGetWidth(result!), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(result!), 1080)
    }
}
