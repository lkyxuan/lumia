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
    case topRight
    case topLeft
}

@Observable
final class RecordingState {
    private(set) var status: RecordingStatus = .idle
    var overlayPosition: OverlayPosition = .bottomRight
    var overlayFraction: CGFloat = 0.20   // circle diameter as fraction of shorter screen edge
    var webcamZoom: CGFloat = 1.0         // 1.0 = normal, 2.0 = 2× zoom into center
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
