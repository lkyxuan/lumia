import Foundation
import CoreGraphics

enum RecordingStatus: Equatable {
    case idle
    case recording
    case paused
}

enum OverlayPosition: Equatable {
    case bottomRight
    case bottomLeft
    case custom(CGPoint)
}

@Observable
final class RecordingState {
    private(set) var status: RecordingStatus = .idle
    var overlayPosition: OverlayPosition = .bottomRight
    private(set) var elapsedSeconds: Int = 0

    var isRecording: Bool { status == .recording }
    var canPause: Bool { status == .recording }
    var canStop: Bool { status == .recording || status == .paused }

    func startRecording() {
        guard status == .idle else { return }
        status = .recording
        elapsedSeconds = 0
    }

    func pauseRecording() {
        guard status == .recording else { return }
        status = .paused
    }

    func resumeRecording() {
        guard status == .paused else { return }
        status = .recording
    }

    func stopRecording() {
        guard status == .recording || status == .paused else { return }
        status = .idle
        elapsedSeconds = 0
    }

    func tick() {
        guard status == .recording else { return }
        elapsedSeconds += 1
    }
}
