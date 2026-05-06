import CoreVideo
import CoreGraphics
import CoreImage

enum FrameCompositor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    static func composite(
        screen: CVPixelBuffer,
        webcam: CVPixelBuffer?,
        overlayRect: CGRect
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(screen)
        let height = CVPixelBufferGetHeight(screen)

        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                   attrs as CFDictionary, &output) == kCVReturnSuccess,
              let output else { return nil }

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

        // CGContext origin is bottom-left, CVPixelBuffer is top-down.
        // Drawing CGImage (top-left) into unflipped CGContext produces correct orientation in the buffer.
        if let screenImage = cgImage(from: screen) {
            ctx.draw(screenImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        if let webcam, let webcamImage = cgImage(from: webcam) {
            // Convert overlayRect (top-left origin) to CGContext bottom-left origin
            let flippedY = CGFloat(height) - overlayRect.maxY
            let dest = CGRect(x: overlayRect.minX, y: flippedY,
                              width: overlayRect.width, height: overlayRect.height)
            ctx.saveGState()
            // Circular clip
            let radius = min(dest.width, dest.height) / 2
            let clipPath = CGPath(roundedRect: dest, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(clipPath)
            ctx.clip()
            ctx.draw(webcamImage, in: dest)
            ctx.restoreGState()
        }

        return output
    }

    private static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}
