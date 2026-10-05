import XCTest
import CoreGraphics
import ImageIO
@testable import CutFuze

final class CanvasTests: XCTestCase {
    func testCanvasMigratesAndRendersLocalBackgroundWithoutChangingOtherVariants() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cg = CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); cg.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        let url = root.appendingPathComponent("source.png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let asset = try await MediaImporter.shared.importFile(url: url, to: root)
        let clip = Clip(assetID: asset.id, kind: .image, presentation: Presentation(fill: false))
        var doc = ProjectDocument(assets: [asset], scenes: [Scene(clips: [clip])])
        let renderer = FrameRenderer(), size = CGSize(width: 90, height: 160)
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: 4)
            data.withUnsafeMutableBytes { p in let context = CGContext(data: p.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!; context.translateBy(x: -5, y: -5); context.draw(image, in: CGRect(x: 0, y: 0, width: 90, height: 160)) }
            return data
        }
        let base = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[0].id), time: .zero, rootURL: root, size: size)
        doc.variants[0].canvas = .init(mode: .solid, color: "#00FF00")
        let solid = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[0].id), time: .zero, rootURL: root, size: size)
        XCTAssertLessThan(pixels(base)[1], 5); XCTAssertGreaterThan(pixels(solid)[1], 240)
        doc.variants[0].canvas = .init(mode: .blurredMedia)
        let blur = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[0].id), time: .zero, rootURL: root, size: size)
        XCTAssertGreaterThan(pixels(blur)[0], 240)
        doc.variants[0].canvas = .init(mode: .image, imageAssetID: asset.id)
        let background = try await renderer.render(plan: .compile(document: doc, variantID: doc.variants[0].id), time: .zero, rootURL: root, size: size)
        XCTAssertGreaterThan(pixels(background)[0], 240)
        XCTAssertNil(doc.variants[1].canvas)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(doc)), doc)
        let legacy = try JSONSerialization.jsonObject(with: DocumentCodec.encode(doc)) as! [String: Any]
        var withoutCanvas = legacy
        withoutCanvas["variants"] = (legacy["variants"] as! [[String: Any]]).map { v in var v = v; v.removeValue(forKey: "canvas"); return v }
        XCTAssertTrue(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: withoutCanvas)).variants.allSatisfy { $0.canvas == nil })
        let exported = root.appendingPathComponent("canvas.mp4")
        let receipt = try await MovieExporter().export(document: doc, variantID: doc.variants[0].id, rootURL: root, settings: .init(longEdge: 160), outputURL: exported) { _ in }
        XCTAssertEqual(receipt.width, 90); XCTAssertEqual(receipt.height, 160)
    }
}
