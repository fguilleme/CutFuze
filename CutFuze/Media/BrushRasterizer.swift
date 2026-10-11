import CoreImage
import CoreGraphics

enum BrushRasterizer {
    static func mask(_ effect: EffectInstance, rect: CGRect) throws -> CIImage {
        let width = max(1, Int(rect.width.rounded(.up))), height = max(1, Int(rect.height.rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { throw DocumentError.invalid("Pinceau") }
        context.setFillColor(gray: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let points = BrushPaths.prefix(effect.strokePath, progress: effect.amount, width: rect.width, height: rect.height)
        if points.count > 1 {
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setLineWidth(min(rect.width, rect.height) * effect.strokeWidth)
            context.setLineCap(.round); context.setLineJoin(.round)
            context.beginPath()
            context.move(to: CGPoint(x: points[0].x * rect.width, y: (1 - points[0].y) * rect.height))
            for point in points.dropFirst() {
                let position = CGPoint(x: point.x * rect.width, y: (1 - point.y) * rect.height)
                if point.startsStroke == true { context.move(to: position) } else { context.addLine(to: position) }
            }
            context.strokePath()
        }
        guard let mask = context.makeImage() else { throw DocumentError.invalid("Pinceau") }
        return CIImage(cgImage: mask).transformed(by: .init(translationX: rect.minX, y: rect.minY)).cropped(to: rect)
    }
}
