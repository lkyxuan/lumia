# Lumia Screen Recorder — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS screen recorder that composites a draggable webcam overlay into the output video, controlled via a floating always-on-top control bar with global shortcuts.

**Architecture:** ScreenCaptureKit delivers screen frames; AVCaptureSession delivers webcam frames. A FrameCompositor blends them per-frame using CoreGraphics, writing to disk via AVAssetWriter. A floating NSPanel serves as the control bar; a second draggable NSPanel shows the live webcam preview and tracks the overlay position.

**Tech Stack:** Swift 5.9+, SwiftUI, ScreenCaptureKit, AVFoundation (AVCaptureSession + AVAssetWriter), CoreGraphics, XCTest, xcodegen

---

## Prerequisites

Install xcodegen if not present:
```bash
brew install xcodegen
```

---

### Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `Lumia/App/LumiaApp.swift`
- Create: `Lumia/App/AppDelegate.swift`
- Create: `Lumia.entitlements`
- Create: `LumiaTests/LumiaTests.swift`

**Step 1: Create `project.yml`**

```yaml
name: Lumia
options:
  bundleIdPrefix: com.lumia
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"

settings:
  base:
    SWIFT_VERSION: "5.9"
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""

targets:
  Lumia:
    type: application
    platform: macOS
    sources: [Lumia]
    settings:
      base:
        INFOPLIST_FILE: Lumia/Info.plist
        CODE_SIGN_ENTITLEMENTS: Lumia.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.lumia.app
    dependencies: []

  LumiaTests:
    type: bundle.unit-test
    platform: macOS
    sources: [LumiaTests]
    dependencies:
      - target: Lumia
```

**Step 2: Create `Lumia.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.camera</key>
    <true/>
</dict>
</plist>
```

**Step 3: Create `Lumia/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSCameraUsageDescription</key>
    <string>Lumia uses your camera for the webcam overlay in recordings.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

> `LSUIElement = true` hides the app from the Dock — it only lives as a floating window.

**Step 4: Create `Lumia/App/LumiaApp.swift`**

```swift
import SwiftUI

@main
struct LumiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

**Step 5: Create `Lumia/App/AppDelegate.swift`**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlBar: ControlBarWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlBar = ControlBarWindowController()
        controlBar?.showWindow(nil)
    }
}
```

**Step 6: Create `LumiaTests/LumiaTests.swift`**

```swift
import XCTest
@testable import Lumia

final class LumiaTests: XCTestCase {}
```

**Step 7: Generate Xcode project and verify it builds**

```bash
cd /Users/qiji/conductor/workspaces/lumia/london
xcodegen generate
xcodebuild -project Lumia.xcodeproj -scheme Lumia -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`  
(Will fail on missing files until later tasks — that's fine, fix compile errors as you go.)

**Step 8: Commit**

```bash
git add project.yml Lumia.entitlements Lumia/ LumiaTests/
git commit -m "chore: scaffold Lumia Xcode project"
```

---

### Task 2: RecordingState Model

**Files:**
- Create: `Lumia/Models/RecordingState.swift`
- Create: `LumiaTests/RecordingStateTests.swift`

**Step 1: Write failing tests**

```swift
// LumiaTests/RecordingStateTests.swift
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
```

**Step 2: Run tests — expect failure**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "error:|FAILED|PASSED"
```

**Step 3: Implement `RecordingState`**

```swift
// Lumia/Models/RecordingState.swift
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
```

**Step 4: Run tests — expect pass**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "FAILED|passed"
```

Expected: `Test Suite ... passed`

**Step 5: Commit**

```bash
git add Lumia/Models/RecordingState.swift LumiaTests/RecordingStateTests.swift
git commit -m "feat: add RecordingState model"
```

---

### Task 3: Camera Capture Module

**Files:**
- Create: `Lumia/Recording/CameraCapture.swift`
- Create: `LumiaTests/CameraCaptureTests.swift`

**Step 1: Write failing test**

```swift
// LumiaTests/CameraCaptureTests.swift
import XCTest
@testable import Lumia

final class CameraCaptureTests: XCTestCase {
    func test_init_doesNotThrow() {
        XCTAssertNoThrow(CameraCapture())
    }

    func test_stop_whenNotStarted_doesNotCrash() {
        let capture = CameraCapture()
        capture.stop()  // should not crash
    }
}
```

**Step 2: Run — expect failure**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "error:|FAILED"
```

**Step 3: Implement `CameraCapture`**

```swift
// Lumia/Recording/CameraCapture.swift
import AVFoundation
import CoreVideo

final class CameraCapture: NSObject {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.lumia.camera", qos: .userInteractive)

    // Latest frame — read from any thread
    private(set) var latestPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()

    override init() {
        super.init()
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    }

    func start() throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw CaptureError.noCamera
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
        lock.withLock { latestPixelBuffer = nil }
    }

    func currentFrame() -> CVPixelBuffer? {
        lock.withLock { latestPixelBuffer }
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.withLock { latestPixelBuffer = buffer }
    }
}

enum CaptureError: Error {
    case noCamera
    case noScreen
}
```

**Step 4: Run tests — expect pass**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "FAILED|passed"
```

**Step 5: Commit**

```bash
git add Lumia/Recording/CameraCapture.swift LumiaTests/CameraCaptureTests.swift
git commit -m "feat: add CameraCapture module"
```

---

### Task 4: Frame Compositor

**Files:**
- Create: `Lumia/Recording/FrameCompositor.swift`
- Create: `LumiaTests/FrameCompositorTests.swift`

**Step 1: Write failing tests**

```swift
// LumiaTests/FrameCompositorTests.swift
import XCTest
import CoreVideo
@testable import Lumia

final class FrameCompositorTests: XCTestCase {
    private func makePixelBuffer(width: Int, height: Int, color: UInt32) -> CVPixelBuffer {
        var buffer: CVPixelBuffer!
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt32.self)
        for i in 0..<(width * height) { ptr[i] = color }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func test_composite_returnsBufferWithCorrectDimensions() {
        let screen = makePixelBuffer(width: 1920, height: 1080, color: 0xFF0000FF)
        let webcam = makePixelBuffer(width: 640, height: 360, color: 0xFF00FF00)
        let rect = CGRect(x: 1600, y: 20, width: 280, height: 158)

        let result = FrameCompositor.composite(screen: screen, webcam: webcam, overlayRect: rect)

        XCTAssertNotNil(result)
        XCTAssertEqual(CVPixelBufferGetWidth(result!), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(result!), 1080)
    }

    func test_composite_withoutWebcam_returnsScreenBuffer() {
        let screen = makePixelBuffer(width: 1920, height: 1080, color: 0xFF0000FF)
        let rect = CGRect(x: 1600, y: 20, width: 280, height: 158)

        let result = FrameCompositor.composite(screen: screen, webcam: nil, overlayRect: rect)

        XCTAssertNotNil(result)
    }
}
```

**Step 2: Run — expect failure**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "error:|FAILED"
```

**Step 3: Implement `FrameCompositor`**

```swift
// Lumia/Recording/FrameCompositor.swift
import CoreVideo
import CoreGraphics
import Accelerate

enum FrameCompositor {
    /// Composites webcam buffer over screen buffer at overlayRect (in screen pixel coords, origin top-left).
    /// Returns a new CVPixelBuffer (same dimensions as screen).
    static func composite(
        screen: CVPixelBuffer,
        webcam: CVPixelBuffer?,
        overlayRect: CGRect
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(screen)
        let height = CVPixelBufferGetHeight(screen)

        // Allocate output buffer
        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &output)
        guard let output else { return nil }

        // Draw into output using CGContext (BGRA, origin top-left)
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(output),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(output),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Flip coordinate system: CGContext origin is bottom-left, we want top-left
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Draw screen
        if let screenImage = makeImage(from: screen) {
            ctx.draw(screenImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Draw webcam overlay
        if let webcam, let webcamImage = makeImage(from: webcam) {
            // overlayRect uses top-left origin — flip Y for CoreGraphics
            let flippedY = CGFloat(height) - overlayRect.maxY
            let dest = CGRect(x: overlayRect.minX, y: flippedY,
                              width: overlayRect.width, height: overlayRect.height)

            // Clip to rounded rect for aesthetic
            let clipPath = CGPath(roundedRect: dest, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.addPath(clipPath)
            ctx.clip()
            ctx.draw(webcamImage, in: dest)
        }

        return output
    }

    private static func makeImage(from buffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
}
```

**Step 4: Run tests — expect pass**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "FAILED|passed"
```

**Step 5: Commit**

```bash
git add Lumia/Recording/FrameCompositor.swift LumiaTests/FrameCompositorTests.swift
git commit -m "feat: add FrameCompositor with CoreGraphics compositing"
```

---

### Task 5: Movie Writer (AVAssetWriter)

**Files:**
- Create: `Lumia/Recording/MovieWriter.swift`
- Create: `LumiaTests/MovieWriterTests.swift`

**Step 1: Write failing tests**

```swift
// LumiaTests/MovieWriterTests.swift
import XCTest
import AVFoundation
@testable import Lumia

final class MovieWriterTests: XCTestCase {
    func test_init_createsOutputURL() throws {
        let writer = try MovieWriter(outputURL: tempURL())
        XCTAssertNotNil(writer)
    }

    func test_finishWithoutStarting_doesNotCrash() throws {
        let writer = try MovieWriter(outputURL: tempURL())
        let exp = expectation(description: "finish")
        writer.finish { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    }
}
```

**Step 2: Run — expect failure**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "error:|FAILED"
```

**Step 3: Implement `MovieWriter`**

```swift
// Lumia/Recording/MovieWriter.swift
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
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                       sourcePixelBufferAttributes: nil)
        if writer.canAdd(input) { writer.add(input) }
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
        guard hasStarted else { completion(nil); return }
        videoInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            completion(self.writer.status == .completed ? self.writer.outputURL : nil)
        }
    }
}
```

**Step 4: Run tests — expect pass**

```bash
xcodebuild test -project Lumia.xcodeproj -scheme LumiaTests 2>&1 | grep -E "FAILED|passed"
```

**Step 5: Commit**

```bash
git add Lumia/Recording/MovieWriter.swift LumiaTests/MovieWriterTests.swift
git commit -m "feat: add MovieWriter with AVAssetWriter"
```

---

### Task 6: Screen Capture Module (ScreenCaptureKit)

**Files:**
- Create: `Lumia/Recording/ScreenCapture.swift`

> ScreenCaptureKit requires an entitlement and a user permission grant — unit testing it in CI is not feasible. Manual verification only.

**Step 1: Implement `ScreenCapture`**

```swift
// Lumia/Recording/ScreenCapture.swift
import ScreenCaptureKit
import CoreVideo

@MainActor
final class ScreenCapture: NSObject {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.lumia.screen", qos: .userInteractive)

    var onFrame: ((CVPixelBuffer, CGSize) -> Void)?

    func requestPermission() async -> Bool {
        do {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noScreen }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        try await stream?.stopCapture()
        stream = nil
    }
}

extension ScreenCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let size = CGSize(width: width, height: height)
        Task { @MainActor [weak self] in
            self?.onFrame?(buffer, size)
        }
    }
}
```

**Step 2: Build — verify no compile errors**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 3: Commit**

```bash
git add Lumia/Recording/ScreenCapture.swift
git commit -m "feat: add ScreenCapture module with ScreenCaptureKit"
```

---

### Task 7: Recording Controller

**Files:**
- Create: `Lumia/Recording/RecordingController.swift`

**Step 1: Implement `RecordingController`**

```swift
// Lumia/Recording/RecordingController.swift
import Foundation
import CoreGraphics
import CoreVideo

@MainActor
final class RecordingController: ObservableObject {
    private let state: RecordingState
    private let screenCapture = ScreenCapture()
    private let cameraCapture = CameraCapture()
    private var movieWriter: MovieWriter?
    private var screenSize: CGSize = .zero
    private var timer: Timer?

    init(state: RecordingState) {
        self.state = state
    }

    func startRecording() async throws {
        let url = desktopURL()
        movieWriter = try MovieWriter(outputURL: url)

        try await cameraCapture.start()

        screenCapture.onFrame = { [weak self] pixelBuffer, size in
            self?.handleScreenFrame(pixelBuffer, size: size)
        }
        try await screenCapture.start()

        state.status = .recording
        state.elapsedSeconds = 0
        startTimer()
    }

    func pauseRecording() {
        guard state.status == .recording else { return }
        state.status = .paused
        timer?.invalidate()
    }

    func resumeRecording() {
        guard state.status == .paused else { return }
        state.status = .recording
        startTimer()
    }

    func stopRecording() async throws {
        timer?.invalidate()
        try await screenCapture.stop()
        cameraCapture.stop()

        await withCheckedContinuation { continuation in
            movieWriter?.finish { _ in continuation.resume() }
        }
        state.status = .idle
    }

    // MARK: - Private

    private func handleScreenFrame(_ screen: CVPixelBuffer, size: CGSize) {
        if screenSize == .zero {
            screenSize = size
            movieWriter?.startWriting(width: Int(size.width), height: Int(size.height))
        }
        guard state.isRecording else { return }

        let overlayRect = resolvedOverlayRect(screenSize: size)
        let webcam = cameraCapture.currentFrame()
        if let composited = FrameCompositor.composite(screen: screen, webcam: webcam, overlayRect: overlayRect) {
            movieWriter?.appendFrame(composited)
        }
    }

    private func resolvedOverlayRect(screenSize: CGSize) -> CGRect {
        let w: CGFloat = 280, h: CGFloat = 158, margin: CGFloat = 24
        switch state.overlayPosition {
        case .bottomRight:
            return CGRect(x: screenSize.width - w - margin,
                          y: screenSize.height - h - margin, width: w, height: h)
        case .bottomLeft:
            return CGRect(x: margin, y: screenSize.height - h - margin, width: w, height: h)
        case .custom(let point):
            return CGRect(origin: point, size: CGSize(width: w, height: h))
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.elapsedSeconds += 1
            }
        }
    }

    private func desktopURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "Lumia_\(formatter.string(from: Date())).mp4"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(name)
    }
}
```

**Step 2: Build — verify no compile errors**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 3: Commit**

```bash
git add Lumia/Recording/RecordingController.swift
git commit -m "feat: add RecordingController orchestrating screen + camera + writer"
```

---

### Task 8: Webcam Preview Window (Draggable)

**Files:**
- Create: `Lumia/Views/WebcamPreviewWindowController.swift`

**Step 1: Implement draggable webcam preview window**

```swift
// Lumia/Views/WebcamPreviewWindowController.swift
import AppKit
import SwiftUI
import AVFoundation

final class WebcamPreviewWindowController: NSWindowController {
    private let state: RecordingState
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(state: RecordingState, session: AVCaptureSession) {
        self.state = state

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 113),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Camera"
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .black

        super.init(window: panel)

        let previewView = NSView(frame: panel.contentView!.bounds)
        previewView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(previewView)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewView.bounds
        previewView.layer = layer
        previewView.wantsLayer = true
        previewLayer = layer

        // Track window position → update overlayPosition in state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        // Position bottom-right by default
        positionBottomRight()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func windowMoved() {
        guard let window, let screen = window.screen else { return }
        let frame = window.frame
        // Convert window origin to top-left screen coordinates for compositor
        let x = frame.minX
        let y = screen.frame.height - frame.maxY
        Task { @MainActor [weak self] in
            self?.state.overlayPosition = .custom(CGPoint(x: x, y: y))
        }
    }

    private func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 24
        let w: CGFloat = 200, h: CGFloat = 113
        let x = screen.frame.maxX - w - margin
        let y = screen.frame.minY + margin
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

**Step 2: Build — verify no compile errors**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 3: Commit**

```bash
git add Lumia/Views/WebcamPreviewWindowController.swift
git commit -m "feat: add draggable webcam preview window"
```

---

### Task 9: Control Bar UI

**Files:**
- Create: `Lumia/Views/ControlBarWindowController.swift`
- Create: `Lumia/Views/ControlBarView.swift`

**Step 1: Implement `ControlBarView`**

```swift
// Lumia/Views/ControlBarView.swift
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
                .help("Start Recording (⌘⇧R)")
            } else {
                Button(action: state.canPause ? onPause : { }) {
                    Image(systemName: state.status == .paused ? "play.circle" : "pause.circle")
                }
                .buttonStyle(.plain)
                .disabled(!state.canPause && state.status != .paused)
                .help("Pause/Resume (⌘⇧P)")

                Button(action: onStop) {
                    Image(systemName: "stop.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(!state.canStop)
                .help("Stop Recording (⌘⇧R)")
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
```

**Step 2: Implement `ControlBarWindowController`**

```swift
// Lumia/Views/ControlBarWindowController.swift
import AppKit
import SwiftUI

final class ControlBarWindowController: NSWindowController {
    private let state = RecordingState()
    private var controller: RecordingController?
    private var webcamWindow: WebcamPreviewWindowController?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.titled, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.level = .screenSaver  // Always on top
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        super.init(window: panel)

        controller = RecordingController(state: state)

        let view = ControlBarView(
            onStart: { Task { @MainActor [weak self] in await self?.startRecording() } },
            onPause: { Task { @MainActor [weak self] in self?.togglePause() } },
            onStop:  { Task { @MainActor [weak self] in await self?.stopRecording() } }
        )
        .environment(state)

        panel.contentView = NSHostingView(rootView: view)
        panel.setFrameOrigin(topCenterOrigin())
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Actions

    private func startRecording() async {
        Task { @MainActor in
            do { try await controller?.startRecording() }
            catch { print("Start failed: \(error)") }
        }
    }

    private func togglePause() {
        if state.status == .recording { controller?.pauseRecording() }
        else if state.status == .paused { controller?.resumeRecording() }
    }

    private func stopRecording() async {
        Task { @MainActor in
            do { try await controller?.stopRecording() }
            catch { print("Stop failed: \(error)") }
        }
    }

    private func topCenterOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let x = (screen.frame.width - 220) / 2
        let y = screen.frame.maxY - 70
        return NSPoint(x: x, y: y)
    }
}
```

**Step 3: Build**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 4: Commit**

```bash
git add Lumia/Views/ControlBarView.swift Lumia/Views/ControlBarWindowController.swift
git commit -m "feat: add floating control bar UI"
```

---

### Task 10: Global Keyboard Shortcuts

**Files:**
- Modify: `Lumia/Views/ControlBarWindowController.swift`

**Step 1: Add global shortcut registration to `ControlBarWindowController.init`**

Add to the end of `init()`:

```swift
// Register global shortcuts
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
    guard let self else { return }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isCommandShift = flags == [.command, .shift]
    guard isCommandShift else { return }

    Task { @MainActor [weak self] in
        guard let self else { return }
        switch event.keyCode {
        case 15: // R
            if self.state.status == .idle { await self.startRecording() }
            else { await self.stopRecording() }
        case 35: // P
            self.togglePause()
        default: break
        }
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 3: Commit**

```bash
git add Lumia/Views/ControlBarWindowController.swift
git commit -m "feat: add global shortcuts ⌘⇧R (record) and ⌘⇧P (pause)"
```

---

### Task 11: Permissions Flow

**Files:**
- Create: `Lumia/App/PermissionsChecker.swift`
- Modify: `Lumia/App/AppDelegate.swift`

**Step 1: Implement `PermissionsChecker`**

```swift
// Lumia/App/PermissionsChecker.swift
import AVFoundation
import AppKit

enum PermissionsChecker {
    static func requestCameraPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            default:
                continuation.resume(returning: false)
            }
        }
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        NSWorkspace.shared.open(url)
    }

    /// Screen recording permission is checked by attempting SCShareableContent.
    /// We surface the result via ScreenCapture.requestPermission().
}
```

**Step 2: Wire permissions into `AppDelegate`**

```swift
// Lumia/App/AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlBar: ControlBarWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let cameraOK = await PermissionsChecker.requestCameraPermission()
            if !cameraOK { showPermissionAlert(for: "Camera") }

            controlBar = ControlBarWindowController()
            controlBar?.showWindow(nil)
        }
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "\(permission) Access Required"
        alert.informativeText = "Lumia needs \(permission.lowercased()) access. Click OK to open System Settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsChecker.openPrivacySettings()
        }
    }
}
```

**Step 3: Build**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 4: Commit**

```bash
git add Lumia/App/PermissionsChecker.swift Lumia/App/AppDelegate.swift
git commit -m "feat: add camera and screen recording permissions flow"
```

---

### Task 12: End-to-End Manual Verification

**Step 1: Build and run**

```bash
xcodebuild -project Lumia.xcodeproj -scheme Lumia build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
open ./build/Debug/Lumia.app
```

**Verification checklist:**

- [ ] App launches — floating control bar appears at top-center of screen
- [ ] Camera permission dialog appears on first launch
- [ ] Webcam preview window appears, draggable to any position
- [ ] Press `⌘⇧R` → recording starts (timer counts up, red dot pulses)
- [ ] Open other apps, browse the web for 10 seconds
- [ ] Press `⌘⇧P` → recording pauses (timer stops)
- [ ] Press `⌘⇧P` again → recording resumes
- [ ] Press `⌘⇧R` → recording stops
- [ ] `.mp4` file appears on Desktop
- [ ] Open the file in QuickTime — screen content visible, webcam overlay in corner
- [ ] Webcam overlay position matches where the preview window was dragged

**Step 2: Final commit**

```bash
git add .
git commit -m "feat: complete Lumia screen recorder v1"
```
