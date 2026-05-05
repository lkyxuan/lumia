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
    var status: RecordingStatus = .idle
    var overlayPosition: OverlayPosition = .bottomRight
    var elapsedSeconds: Int = 0

    var isRecording: Bool { status == .recording }
    var canPause: Bool { status == .recording }
    var canStop: Bool { status == .recording || status == .paused }
}
