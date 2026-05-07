import CoreVideo

enum FrameCompositor {

    static func composite(
        screen: CVPixelBuffer,
        webcam: CVPixelBuffer?,
        overlayFraction: CGFloat = 0.20,
        webcamZoom: CGFloat = 1.0,
        overlayPosition: OverlayPosition = .bottomRight
    ) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(screen)
        let h = CVPixelBufferGetHeight(screen)

        var output: CVPixelBuffer?
        guard CVPixelBufferCreate(
            nil, w, h, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &output
        ) == kCVReturnSuccess, let output else { return nil }

        // ── 1. Copy screen ─────────────────────────────────────────────────
        CVPixelBufferLockBaseAddress(screen, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        let srcBase = CVPixelBufferGetBaseAddress(screen)!
        let dstBase = CVPixelBufferGetBaseAddress(output)!
        let srcBpr  = CVPixelBufferGetBytesPerRow(screen)
        let dstBpr  = CVPixelBufferGetBytesPerRow(output)
        for row in 0..<h {
            memcpy(dstBase + row * dstBpr, srcBase + row * srcBpr, min(srcBpr, dstBpr))
        }
        CVPixelBufferUnlockBaseAddress(output, [])
        CVPixelBufferUnlockBaseAddress(screen, .readOnly)

        // ── 2. Blit webcam circle ──────────────────────────────────────────
        if let webcam {
            let diameter = Int((CGFloat(min(w, h)) * overlayFraction).rounded())
            let margin   = Int((CGFloat(diameter) * 0.08).rounded())
            let rect: CGRect
            switch overlayPosition {
            case .bottomRight:
                rect = CGRect(x: w - diameter - margin, y: h - diameter - margin,
                              width: diameter, height: diameter)
            case .bottomLeft:
                rect = CGRect(x: margin, y: h - diameter - margin,
                              width: diameter, height: diameter)
            case .topRight:
                rect = CGRect(x: w - diameter - margin, y: margin,
                              width: diameter, height: diameter)
            case .topLeft:
                rect = CGRect(x: margin, y: margin,
                              width: diameter, height: diameter)
            }
            blit(webcam, into: output, at: rect, zoom: webcamZoom)
        }

        return output
    }

    // Center-crop src (with zoom), scale to rect, apply circular mask.
    private static func blit(
        _ src: CVPixelBuffer,
        into dst: CVPixelBuffer,
        at rect: CGRect,
        zoom: CGFloat
    ) {
        let srcW = CVPixelBufferGetWidth(src)
        let srcH = CVPixelBufferGetHeight(src)
        let dstW = CVPixelBufferGetWidth(dst)
        let dstH = CVPixelBufferGetHeight(dst)

        let x0 = max(0, Int(rect.minX));  let x1 = min(dstW, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY));  let y1 = min(dstH, Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }
        guard let sb = CVPixelBufferGetBaseAddress(src),
              let db = CVPixelBufferGetBaseAddress(dst) else { return }

        let sBpr = CVPixelBufferGetBytesPerRow(src)
        let dBpr = CVPixelBufferGetBytesPerRow(dst)
        let ow = x1 - x0;  let oh = y1 - y0

        // Square center-crop of source, then shrink by zoom
        let baseCrop = min(srcW, srcH)
        let cropSize = max(1, Int((CGFloat(baseCrop) / zoom).rounded()))
        let cropX0   = (srcW - cropSize) / 2
        let cropY0   = (srcH - cropSize) / 2

        // Circular clip
        let cx = ow / 2;  let cy = oh / 2
        let r2 = cx * cx

        for row in 0..<oh {
            let dy = row - cy
            let sRow = cropY0 + row * cropSize / oh
            let sPtr = sb.advanced(by: sRow * sBpr).assumingMemoryBound(to: UInt32.self)
            let dPtr = db.advanced(by: (y0 + row) * dBpr + x0 * 4).assumingMemoryBound(to: UInt32.self)
            for col in 0..<ow {
                let dx = col - cx
                guard dx * dx + dy * dy <= r2 else { continue }
                let sCol = cropX0 + col * cropSize / ow
                dPtr[col] = sPtr[sCol]
            }
        }
    }
}
