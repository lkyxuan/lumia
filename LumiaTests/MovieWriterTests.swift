import XCTest
import AVFoundation
@testable import Lumia

final class MovieWriterTests: XCTestCase {
    func test_init_succeeds() throws {
        XCTAssertNoThrow(try MovieWriter(outputURL: tempURL()))
    }

    func test_finishWithoutStarting_callsCompletionWithNil() throws {
        let writer = try MovieWriter(outputURL: tempURL())
        let exp = expectation(description: "finish")
        var resultURL: URL?
        writer.finish { url in
            resultURL = url
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertNil(resultURL)
    }

    func test_startWritingAndFinish_producesFile() throws {
        let url = tempURL()
        let writer = try MovieWriter(outputURL: url)
        writer.startWriting(width: 640, height: 360)

        // Append a few blank frames
        for _ in 0..<5 {
            if let buffer = makePixelBuffer(width: 640, height: 360) {
                writer.appendFrame(buffer)
            }
        }

        let exp = expectation(description: "finish")
        var resultURL: URL?
        writer.finish { url in
            resultURL = url
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertNotNil(resultURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &buffer)
        return buffer
    }
}
