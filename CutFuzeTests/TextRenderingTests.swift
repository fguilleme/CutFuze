import XCTest
import CoreGraphics
@testable import CutFuze

final class TextRenderingTests: XCTestCase {
    private func inkBounds(_ image: CGImage) -> CGRect {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { p in
            let context = CGContext(data: p.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var minX = image.width, maxX = 0, minY = image.height, maxY = 0
        for y in 0..<image.height { for x in 0..<image.width where bytes[(y * image.width + x) * 4 + 3] > 32 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
    func testLetterAndLineSpacingChangeRealTextGeometry() throws {
        var style = Presentation(textSize: 0.1)
        let normal = try TextRasterizer.render(text: "ÉTÉ\nÉTÉ", presentation: style, size: CGSize(width: 300, height: 300))
        style.textLetterSpacing = 0.3; style.textLineSpacing = 0.7
        let spaced = try TextRasterizer.render(text: "ÉTÉ\nÉTÉ", presentation: style, size: CGSize(width: 300, height: 300))
        XCTAssertGreaterThan(inkBounds(spaced).width, inkBounds(normal).width + 10)
        XCTAssertGreaterThan(inkBounds(spaced).height, inkBounds(normal).height + 10)
    }
}
