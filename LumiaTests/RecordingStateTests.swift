import XCTest
@testable import Lumia

final class RecordingStateTests: XCTestCase {
    func test_initialState_isIdle() {
        let state = RecordingState()
        XCTAssertEqual(state.status, .idle)
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.canPause)
        XCTAssertFalse(state.canStop)
    }

    func test_overlayPosition_defaultsToBottomRight() {
        let state = RecordingState()
        XCTAssertEqual(state.overlayPosition, .bottomRight)
    }

    func test_startRecording_transitionsFromIdle() {
        let state = RecordingState()
        state.startRecording()
        XCTAssertEqual(state.status, .recording)
        XCTAssertTrue(state.isRecording)
        XCTAssertTrue(state.canPause)
        XCTAssertTrue(state.canStop)
    }

    func test_startRecording_resetsElapsedSeconds() {
        let state = RecordingState()
        state.startRecording()
        state.tick()
        state.tick()
        state.stopRecording()
        state.startRecording()
        XCTAssertEqual(state.elapsedSeconds, 0)
    }

    func test_pauseRecording_transitionsFromRecording() {
        let state = RecordingState()
        state.startRecording()
        state.pauseRecording()
        XCTAssertEqual(state.status, .paused)
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.canPause)
        XCTAssertTrue(state.canStop)
    }

    func test_resumeRecording_transitionsFromPaused() {
        let state = RecordingState()
        state.startRecording()
        state.pauseRecording()
        state.resumeRecording()
        XCTAssertEqual(state.status, .recording)
        XCTAssertTrue(state.isRecording)
    }

    func test_stopRecording_transitionsToIdle() {
        let state = RecordingState()
        state.startRecording()
        state.stopRecording()
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.elapsedSeconds, 0)
    }

    func test_tick_incrementsElapsedSeconds_whenRecording() {
        let state = RecordingState()
        state.startRecording()
        state.tick()
        state.tick()
        XCTAssertEqual(state.elapsedSeconds, 2)
    }

    func test_tick_doesNotIncrement_whenPaused() {
        let state = RecordingState()
        state.startRecording()
        state.pauseRecording()
        state.tick()
        XCTAssertEqual(state.elapsedSeconds, 0)
    }
}
