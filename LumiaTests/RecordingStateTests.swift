import XCTest
@testable import Lumia

final class RecordingStateTests: XCTestCase {
    func test_initialState_isIdle() {
        let state = RecordingState()
        XCTAssertEqual(state.status, .idle)
    }

    func test_startRecording_transitionsToRecording() {
        let state = RecordingState()
        state.status = .recording
        XCTAssertEqual(state.status, .recording)
    }

    func test_overlayPosition_defaultsToBottomRight() {
        let state = RecordingState()
        XCTAssertEqual(state.overlayPosition, OverlayPosition.bottomRight)
    }
}
