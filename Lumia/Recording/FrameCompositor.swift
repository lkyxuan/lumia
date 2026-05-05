import CoreVideo
import CoreGraphics
import VideoToolbox

enum FrameCompositor {
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

        // CGContext origin is bottom-left; flip to top-left
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        if let screenImage = cgImage(from: screen) {
            ctx.draw(screenImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        if let webcam, let webcamImage = cgImage(from: webcam) {
            // overlayRect uses top-left origin; flip Y for CGContext
            let flippedY = CGFloat(height) - overlayRect.maxY
            let dest = CGRect(x: overlayRect.minX, y: flippedY,
                              width: overlayRect.width, height: overlayRect.height)
            ctx.saveGState()
            let clipPath = CGPath(roundedRect: dest, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.addPath(clipPath)
            ctx.clip()
            ctx.draw(webcamImage, in: dest)
            ctx.restoreGState()
        }

        return output
    }

    private static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        return image
    }
}
