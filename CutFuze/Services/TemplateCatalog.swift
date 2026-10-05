import CryptoKit
import Foundation
import UIKit

struct TemplateDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let accent: String
    let sceneTitles: [String]
    let durations: [Double]
    let transitions: [TransitionKind]
    let theme: Int
    var duration: Double {
        durations.reduce(0, +) - Double(max(0, durations.count - 1)) * 0.4
    }
}

/// All presets become ordinary editable documents; there is no separate template renderer.
@MainActor
enum TemplateCatalog {
    static let all: [TemplateDefinition] = [
        .init(id: "portrait", name: "Une voix, une idée", subtitle: "Portrait · 3 scènes", symbol: "person.crop.rectangle", accent: "#EBA65A", sceneTitles: ["Voici mon idée", "Ce qui m’inspire", "À vous de jouer"], durations: [5, 9, 5], transitions: [.dissolve, .black], theme: 0),
        .init(id: "before-after", name: "Un autre regard", subtitle: "Avant / après · 2 scènes", symbol: "rectangle.lefthalf.inset.filled", accent: "#88B6AB", sceneTitles: ["AVANT", "APRÈS"], durations: [4, 6], transitions: [.wipe], theme: 1),
        .init(id: "slideshow", name: "Petites collections", subtitle: "Diaporama · 6 scènes", symbol: "photo.stack", accent: "#D9A8C5", sceneTitles: ["Un détail", "Une couleur", "Une rencontre", "Un détour", "Un sourire", "À garder"], durations: [3, 3, 4, 3, 4, 5], transitions: [.dissolve, .slide, .dissolve, .slide, .black], theme: 2),
        .init(id: "travel", name: "Carnet de route", subtitle: "Voyage · 4 étapes", symbol: "map", accent: "#7DB6CA", sceneTitles: ["Le départ", "Prendre le large", "Faire une pause", "Le chemin du retour"], durations: [4, 8, 7, 5], transitions: [.slide, .dissolve, .zoom], theme: 3),
        .init(id: "product", name: "Objet singulier", subtitle: "Présentation · 3 détails", symbol: "cube.transparent", accent: "#DFBA79", sceneTitles: ["Un objet, une histoire", "Pensé dans le détail", "Pour le quotidien"], durations: [4, 7, 6], transitions: [.white, .blur], theme: 4),
        .init(id: "rhythm", name: "En cadence", subtitle: "Rythme · 8 plans courts", symbol: "waveform", accent: "#E68272", sceneTitles: ["UN", "DEUX", "TROIS", "QUATRE", "ON", "PREND", "LE", "RYTHME"], durations: [2, 2, 2, 2, 2, 2, 2, 4], transitions: [.glitch, .white, .glitch, .zoom, .white, .slide, .zoom], theme: 5),
        .init(id: "tutorial", name: "Le geste juste", subtitle: "Tutoriel · 4 étapes", symbol: "hand.draw", accent: "#AFBE8B", sceneTitles: ["Le nécessaire", "1. Préparer", "2. Assembler", "3. Admirer"], durations: [5, 7, 8, 5], transitions: [.wipe, .wipe, .dissolve], theme: 6),
        .init(id: "journal", name: "Aujourd’hui", subtitle: "Journal · 5 instants", symbol: "book.pages", accent: "#CAA583", sceneTitles: ["Ce matin", "En chemin", "La lumière", "Une pause", "Ce soir"], durations: [4, 5, 6, 5, 5], transitions: [.black, .dissolve, .black, .dissolve], theme: 7),
        .init(id: "invitation", name: "On se retrouve", subtitle: "Invitation · 3 cartes", symbol: "envelope.open", accent: "#BBABCF", sceneTitles: ["Vous êtes invités", "Quand et où ?", "Venez comme vous êtes"], durations: [4, 8, 5], transitions: [.zoom, .dissolve], theme: 8),
        .init(id: "recipe", name: "À partager", subtitle: "Recette · 5 étapes", symbol: "fork.knife", accent: "#C5B974", sceneTitles: ["À la table", "Les ingrédients", "Le tour de main", "Un peu de patience", "Bon appétit"], durations: [3, 6, 8, 4, 5], transitions: [.slide, .wipe, .blur, .dissolve], theme: 9),
        .init(id: "portfolio", name: "Trois réalisations", subtitle: "Portfolio · 4 chapitres", symbol: "square.grid.3x1.below.line.grid.1x2", accent: "#7EABBA", sceneTitles: ["Une sélection", "Étude 01", "Étude 02", "Étude 03"], durations: [3, 7, 7, 7], transitions: [.black, .white, .black], theme: 10),
        .init(id: "letter", name: "Une lettre en images", subtitle: "Récit · 4 fragments", symbol: "text.alignleft", accent: "#C59D99", sceneTitles: ["Chère lumière,", "Je me souviens", "De ces petites choses", "À très bientôt"], durations: [6, 9, 7, 5], transitions: [.dissolve, .blur, .dissolve], theme: 11)
    ]

    static func make(template: TemplateDefinition, in rootURL: URL) async throws -> ProjectDocument {
        let resources = try SyntheticResources.make(in: rootURL, theme: template.theme)
        var document = ProjectDocument(title: template.name, collection: "Modèles", assets: resources.images)
        for (index, title) in template.sceneTitles.enumerated() {
            let duration = template.durations[index]
            let image = resources.images[index % resources.images.count]
            var background = Clip(assetID: image.id, kind: .image, duration: .init(seconds: duration), sourceDuration: .init(seconds: duration))
            background.presentation.scale = 1 + Double(template.theme % 3) * 0.035
            background.keyframes = [
                .init(time: .zero, property: .scale, value: background.presentation.scale),
                .init(time: .init(seconds: duration), property: .scale, value: background.presentation.scale + 0.10, easing: .easeInOut)
            ]
            var heading = Clip(kind: .text, start: .init(seconds: 0.25), duration: .init(seconds: duration - 0.5), sourceDuration: .init(seconds: duration - 0.5), text: title, layer: 10)
            heading.presentation.y = [0.28, 0.5, 0.74][template.theme % 3]
            heading.presentation.textSize = template.id == "rhythm" ? 0.13 : 0.072
            heading.presentation.textAlignment = template.id == "letter" ? "left" : "center"
            heading.presentation.textShadow = 0.45
            heading.keyframes = [
                .init(time: .zero, property: .opacity, value: 0),
                .init(time: .init(seconds: 0.35), property: .opacity, value: 1, easing: .easeOut)
            ]
            var clips = [background, heading]
            if template.id == "portrait" || template.id == "tutorial" || template.id == "letter" {
                var caption = Clip(kind: .text, start: .init(seconds: 1), duration: .init(seconds: duration - 1.25), sourceDuration: .init(seconds: duration - 1.25), text: "Votre texte, votre histoire.", layer: 20, isCaption: true)
                caption.presentation.y = 0.86
                caption.presentation.textSize = 0.041
                caption.presentation.textBackgroundOpacity = 0.6
                clips.append(caption)
            }
            document.scenes.append(Scene(title: title, narration: "Remplacez ce texte par votre narration.", duration: .init(seconds: duration), clips: clips, transition: .init(kind: index < template.transitions.count ? template.transitions[index] : .none, duration: .init(seconds: 0.4))))
        }
        configureFormats(&document)
        return document
    }

    static func configureFormats(_ document: inout ProjectDocument) {
        for index in document.variants.indices {
            for clip in document.allClips where clip.kind == .image || clip.kind == .text {
                var presentation = clip.presentation
                switch index {
                case 0:
                    if clip.kind == .image { presentation.x = 0.46; presentation.scale = 1.02 }
                    else { presentation.textSize *= 1.03 }
                case 1:
                    if clip.kind == .image { presentation.x = 0.55; presentation.scale = 1.16 }
                    else { presentation.y = clip.isCaption ? 0.84 : 0.38 }
                default:
                    if clip.kind == .image { presentation.x = 0.5; presentation.scale = 1 }
                    else { presentation.y = clip.isCaption ? 0.82 : 0.32; presentation.textSize *= 0.9 }
                }
                document.variants[index].overrides[clip.id.uuidString] = presentation
            }
        }
    }
}

@MainActor
enum DemoFactory {
    static func make(in rootURL: URL) async throws -> ProjectDocument {
        let resources = try SyntheticResources.make(in: rootURL, theme: 3)
        let sound = try SyntheticResources.makeReferenceSound(in: rootURL, duration: 30)
        var document = ProjectDocument(title: "Trente secondes de lumière", collection: "Exemples", assets: resources.images + [sound])
        let titles = ["Lever les yeux", "Trouver son rythme", "Garder la lumière"]
        let narratives = ["Une histoire commence par un regard.", "On suit les lignes, les formes, le mouvement.", "Trois formats. Une même histoire à partager."]
        for index in 0..<3 {
            let duration: Double = 10.4
            let image = Clip(assetID: resources.images[index].id, kind: .image, duration: .init(seconds: duration), sourceDuration: .init(seconds: duration), keyframes: [.init(time: .zero, property: .scale, value: 1), .init(time: .init(seconds: duration), property: .scale, value: 1.1, easing: .easeInOut)])
            var heading = Clip(kind: .text, start: .init(seconds: 0.6), duration: .init(seconds: 8.5), sourceDuration: .init(seconds: 8.5), text: titles[index], layer: 10)
            heading.presentation.y = 0.28
            heading.presentation.textSize = 0.075
            heading.presentation.textShadow = 0.6
            heading.keyframes = [.init(time: .zero, property: .opacity, value: 0), .init(time: .init(seconds: 0.6), property: .opacity, value: 1)]
            var caption = Clip(kind: .text, start: .init(seconds: 1), duration: .init(seconds: 8), sourceDuration: .init(seconds: 8), text: narratives[index], layer: 20, isCaption: true)
            caption.presentation.y = 0.85
            caption.presentation.textSize = 0.044
            caption.presentation.textBackgroundOpacity = 0.6
            document.scenes.append(.init(title: titles[index], narration: narratives[index], duration: .init(seconds: duration), clips: [image, heading, caption], transition: .init(kind: index < 2 ? [.dissolve, .wipe][index] : .none, duration: .init(seconds: 0.6))))
        }
        document.globalClips = [.init(assetID: sound.id, kind: .audio, duration: .init(seconds: 30), sourceDuration: .init(seconds: 30), volume: 0.45, fadeIn: .init(seconds: 0.5), fadeOut: .init(seconds: 1), layer: -1)]
        TemplateCatalog.configureFormats(&document)
        return document
    }
}

/// Original geometrical artwork and synthesized tones. No bundled stock or remote media.
@MainActor
enum SyntheticResources {
    struct Images { let images: [MediaAsset] }
    static func make(in root: URL, theme: Int) throws -> Images {
        let folder = root.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var assets: [MediaAsset] = []
        for index in 0..<3 {
            let relative = "Assets/illustration-\(theme)-\(index)-\(UUID().uuidString).png"
            let url = root.appendingPathComponent(relative)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1280, height: 960), format: format)
            let png = renderer.pngData { context in
                let ctx = context.cgContext
                let hue = CGFloat((theme * 23 + index * 47) % 360) / 360
                let sky = UIColor(hue: hue, saturation: 0.35, brightness: 0.34, alpha: 1)
                let light = UIColor(hue: hue + 0.07, saturation: 0.42, brightness: 0.72, alpha: 1)
                ctx.setFillColor(sky.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 960))
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [sky.cgColor, light.cgColor] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1280, y: 960), options: [])
                ctx.setFillColor(UIColor(red: 0.98, green: 0.77, blue: 0.48, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: 550 + index * 70, y: 280 - index * 20, width: 220, height: 220))
                for layer in 0..<4 {
                    let y = CGFloat(580 + layer * 105)
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: -100, y: 960))
                    path.addLine(to: CGPoint(x: -100, y: y + 50))
                    path.addCurve(to: CGPoint(x: 1400, y: y - 60), control1: CGPoint(x: 250, y: y - 340 + CGFloat(index * 70)), control2: CGPoint(x: 730, y: y + 240 - CGFloat(theme * 8)))
                    path.addLine(to: CGPoint(x: 1400, y: 960))
                    path.closeSubpath()
                    ctx.setFillColor(UIColor(hue: hue + CGFloat(layer) * 0.025, saturation: 0.4, brightness: 0.23 + CGFloat(layer) * 0.07, alpha: 1).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.24).cgColor)
                ctx.setLineWidth(2)
                for line in 0..<5 {
                    ctx.stroke(CGRect(x: 170 + line * 26, y: 160 + line * 26, width: 200, height: 270))
                }
            }
            try png.write(to: url, options: .atomic)
            assets.append(.init(relativePath: relative, kind: .image, name: "Lumière \(index + 1)", width: 1280, height: 960, sha256: try digest(url)))
        }
        return Images(images: assets)
    }

    static func makeReferenceSound(in root: URL, duration: Double) throws -> MediaAsset {
        let relative = "Assets/reference-\(UUID().uuidString).wav"
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sampleRate = 48_000
        let frameCount = Int(duration * Double(sampleRate))
        var header = Data()
        func string(_ value: String) { header.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
        string("RIFF"); u32(UInt32(36 + frameCount * 2)); string("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16); string("data"); u32(UInt32(frameCount * 2))
        try header.write(to: url, options: .atomic)
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        try output.seekToEnd()
        for start in stride(from: 0, to: frameCount, by: 8192) {
            var block = Data(capacity: 16_384)
            for index in start..<min(frameCount, start + 8192) {
                let t = Double(index) / Double(sampleRate)
                let beat = t.truncatingRemainder(dividingBy: 1)
                let pulse = exp(-beat * 18) * sin(2 * .pi * 880 * t) * 0.11
                let chord = (sin(2 * .pi * 220 * t) + sin(2 * .pi * 277.1826 * t) + sin(2 * .pi * 329.6276 * t)) * 0.035
                let envelope = min(1, min(t / 0.5, (duration - t) / 0.8))
                var sample = Int16(max(-1, min(1, (pulse + chord) * envelope)) * 32767).littleEndian
                withUnsafeBytes(of: &sample) { block.append(contentsOf: $0) }
            }
            try output.write(contentsOf: block)
        }
        try output.synchronize()
        return .init(relativePath: relative, kind: .audio, name: "Repère sonore original", duration: .init(seconds: duration), sha256: try digest(url), hasAudio: true)
    }

    private static func digest(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        while let block = try input.read(upToCount: 65_536), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
