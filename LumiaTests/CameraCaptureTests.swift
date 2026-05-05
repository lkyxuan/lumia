import XCTest
@testable import Lumia

final class CameraCaptureTests: XCTestCase {
    func test_init_doesNotThrow() {
        XCTAssertNoThrow(CameraCapture())
    }

    func test_stop_whenNotStarted_doesNotCrash() {
        let capture = CameraCapture()
        capture.stop()
    }

    func test_currentFrame_returnsNilBeforeStart() {
        let capture = CameraCapture()
        XCTAssertNil(capture.currentFrame())
    }
}
