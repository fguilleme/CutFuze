import XCTest
import CoreGraphics
import UIKit
@testable import CutFuze

final class TextRenderingTests: XCTestCase {
    func testBackgroundShapesPersistAndRenderDistinctColoredBackdrops() throws {
        XCTAssertEqual(try JSONDecoder().decode(Presentation.self, from: Data("{}".utf8)).textBackgroundShape, .rounded)
        var rasters = Set<Data>()
        for shape in TextBackgroundShape.allCases {
            var style = Presentation(textSize: 0.065, background: "#EF4444", textBackgroundOpacity: 1)
            style.textBackgroundShape = shape
            let decoded = try JSONDecoder().decode(Presentation.self, from: JSONEncoder().encode(style))
            XCTAssertEqual(decoded, style)
            let image = try TextRasterizer.render(text: "Bonjour\nle monde", presentation: decoded, size: CGSize(width: 640, height: 640))
            let png = try XCTUnwrap(UIImage(cgImage: image).pngData())
            rasters.insert(png)
            let bounds = inkBounds(image)
            XCTAssertGreaterThan(bounds.width, 70)
            XCTAssertGreaterThan(bounds.height, 40)
            XCTAssertGreaterThan(bounds.minX, 0)
            XCTAssertLessThan(bounds.maxX, 640)
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "text-background-\(shape.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(rasters.count, TextBackgroundShape.allCases.count)
    }

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

    func testTextSizeChangesRenderedCaptionGeometry() throws {
        let small = try TextRasterizer.render(text: "Sous-titre", presentation: Presentation(textSize: 0.04), size: CGSize(width: 600, height: 400))
        let large = try TextRasterizer.render(text: "Sous-titre", presentation: Presentation(textSize: 0.12), size: CGSize(width: 600, height: 400))
        XCTAssertGreaterThan(inkBounds(large).width, inkBounds(small).width * 2)
        XCTAssertGreaterThan(inkBounds(large).height, inkBounds(small).height * 2)
    }
}
