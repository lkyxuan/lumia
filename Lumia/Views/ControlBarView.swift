import SwiftUI

struct ControlBarView: View {
    @Environment(RecordingState.self) var state
    let onStart: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.isRecording ? Color.red : Color.gray)
                .frame(width: 10, height: 10)
                .opacity(state.isRecording ? 1 : 0.4)

            Text(formattedTime)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 48)

            Divider().frame(height: 16)

            if state.status == .idle {
                Button(action: onStart) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("开始录制 (⌘⇧R)")
            } else {
                Button(action: state.status == .paused ? onPause : onPause) {
                    Image(systemName: state.status == .paused ? "play.circle" : "pause.circle")
                }
                .buttonStyle(.plain)
                .help(state.status == .paused ? "继续录制 (⌘⇧P)" : "暂停录制 (⌘⇧P)")

                Button(action: onStop) {
                    Image(systemName: "stop.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(!state.canStop)
                .help("停止录制 (⌘⇧R)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var formattedTime: String {
        let m = state.elapsedSeconds / 60
        let s = state.elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
