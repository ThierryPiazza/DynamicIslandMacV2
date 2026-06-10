import AppKit

extension NSImage {
    /// Bitmap ridimensionata (lato massimo `maxSide`), opzionalmente ritagliata
    /// quadrata al centro. Rasterizza una volta sola in un buffer piccolo:
    /// tenere in RAM screenshot 5K o thumbnail 1280×720 costa decine di MB.
    func resizedBitmap(maxSide: CGFloat, squareCrop: Bool = false) -> NSImage {
        guard var cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }

        if squareCrop, cg.width != cg.height {
            let side = min(cg.width, cg.height)
            let crop = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2,
                              width: side, height: side)
            cg = cg.cropping(to: crop) ?? cg
        }

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h, 1))
        guard scale < 1 else {
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }

        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }

        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let scaled = ctx.makeImage() else {
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }
        return NSImage(cgImage: scaled, size: NSSize(width: tw, height: th))
    }
}
