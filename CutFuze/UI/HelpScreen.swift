import SwiftUI

enum HelpDocument: String, CaseIterable, Identifiable {
    case guide = "UserGuide"
    case tutorial = "Tutorial"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .guide: AppLocalization.bilingual("Aide", "Help")
        case .tutorial: AppLocalization.bilingual("Premiers pas", "First steps")
        }
    }
    var symbol: String { self == .guide ? "book" : "play.rectangle" }
    func content(language: String) -> String? {
        guard let url = Bundle.main.url(forResource: "\(rawValue).\(language)", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Task-based help and a resumable walkthrough, available offline.
struct HelpScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var document: HelpDocument = .tutorial
    @AppStorage("helpTutorialPage") private var tutorialPage = 0
    @State private var topicID: Int?
    private var language: String { AppLocalization.isFrench ? "fr" : "en" }
    private var blocks: [HelpBlock] { HelpBlock.parse(document.content(language: language) ?? "") }
    private var chapters: [HelpChapter] { HelpChapter.sections(in: blocks) }
    private var currentPage: Int { min(max(0, tutorialPage), chapters.count) }
    private var showingTopics: Bool { document == .guide && topicID == nil }
    private var visibleBlocks: [HelpBlock] {
        if document == .tutorial {
            return currentPage == 0 ? intro : chapters[currentPage - 1].blocks
        }
        return chapters.first(where: { $0.id == topicID })?.blocks ?? intro
    }
    private var intro: [HelpBlock] { Array(blocks.prefix(while: { !$0.isSection })) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    Picker(AppLocalization.bilingual("Aide", "Help"), selection: $document) {
                        ForEach(HelpDocument.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).padding().accessibilityIdentifier("helpDocumentPicker")
                    if document == .tutorial && currentPage > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.bilingual("Étape \(currentPage) sur \(chapters.count)", "Step \(currentPage) of \(chapters.count)"))
                                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("tutorialProgress")
                            ProgressView(value: Double(currentPage), total: Double(max(1, chapters.count)))
                        }.padding(.horizontal, 20).padding(.bottom, 12)
                    } else if document == .guide && !showingTopics {
                        Button { topicID = nil } label: {
                            Label(AppLocalization.bilingual("Tous les sujets", "All topics"), systemImage: "chevron.left")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.padding(.horizontal, 20).accessibilityIdentifier("helpAllTopics")
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Color.clear.frame(height: 0).id("helpTop")
                            if blocks.isEmpty {
                                ContentUnavailableView(AppLocalization.bilingual("Guide indisponible", "Guide unavailable"), systemImage: "book.closed")
                            }
                            ForEach(Array(visibleBlocks.enumerated()), id: \.offset) { index, block in
                                blockView(block).id(index)
                            }
                            if showingTopics {
                                ForEach(chapters) { chapter in
                                    Button { topicID = chapter.id } label: {
                                        HStack(alignment: .center, spacing: 12) {
                                            Text(chapter.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                        }.padding(16).frame(minHeight: 52)
                                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).accessibilityLabel(chapter.title).accessibilityIdentifier("helpTopic-\(chapter.id)")
                                }
                            }
                        }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                    }.accessibilityIdentifier("helpContent")
                    .environment(\.openURL, OpenURLAction { url in
                        if let fragment = url.fragment,
                           let chapter = chapters.first(where: { $0.blocks.first?.anchor == fragment }) {
                            if document == .guide { topicID = chapter.id }
                            else if let index = chapters.firstIndex(where: { $0.id == chapter.id }) { tutorialPage = index + 1 }
                            return .handled
                        }
                        if url.lastPathComponent.contains("UserGuide") { document = .guide; return .handled }
                        if url.lastPathComponent.contains("Tutorial") { document = .tutorial; return .handled }
                        return .discarded
                    })
                    .onChange(of: document) { _, _ in topicID = nil; proxy.scrollTo("helpTop", anchor: .top) }
                    .onChange(of: topicID) { _, _ in proxy.scrollTo("helpTop", anchor: .top) }
                    .onChange(of: currentPage) { _, _ in proxy.scrollTo("helpTop", anchor: .top) }
                    if document == .tutorial && !chapters.isEmpty { tutorialNavigation }
                }
                .navigationTitle(AppLocalization.bilingual("Aide et tutoriel", "Help and tutorial"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Fermer")) { dismiss() }.accessibilityIdentifier("closeHelp")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                                Button(chapter.title) {
                                    if document == .guide { topicID = chapter.id }
                                    else { tutorialPage = index + 1 }
                                }.accessibilityIdentifier("helpSection-\(chapter.id)")
                            }
                        } label: { Image(systemName: "list.bullet").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel(AppLocalization.bilingual("Sommaire", "Contents"))
                        .accessibilityIdentifier("helpContents")
                    }
                }
            }
        }.preferredColorScheme(.light)
    }

    private var tutorialNavigation: some View {
        HStack(spacing: 16) {
            if currentPage > 0 {
                Button { tutorialPage = currentPage - 1 } label: {
                    Label(AppLocalization.bilingual("Précédent", "Previous"), systemImage: "chevron.left").frame(minHeight: 44)
                }.accessibilityIdentifier("tutorialPrevious")
            }
            Spacer(minLength: 0)
            Button {
                if currentPage == chapters.count { tutorialPage = 0; dismiss() }
                else { tutorialPage = currentPage + 1 }
            } label: {
                Text(currentPage == 0 ? AppLocalization.bilingual("Commencer", "Start")
                     : currentPage == chapters.count ? L("Terminé")
                     : AppLocalization.bilingual("Étape suivante", "Next step"))
                    .font(.headline).padding(.horizontal, 16).frame(minHeight: 44)
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("tutorialNext")
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }

    @ViewBuilder private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text).font(level == 1 ? .title.bold() : .title2.bold())
                .accessibilityAddTraits(.isHeader).padding(.top, level == 1 ? 0 : 14)
        case .paragraph(let text):
            Text(richText(text)).font(.body).textSelection(.enabled)
        case .item(let prefix, let text):
            HStack(alignment: .top, spacing: 10) {
                Text(prefix).foregroundStyle(.secondary).frame(minWidth: 22, alignment: .leading)
                Text(richText(text)).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                        GridRow {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                Text(richText(cell)).font(index == 0 ? .subheadline.bold() : .subheadline)
                                    .frame(width: cells.count > 2 ? 160 : 220, alignment: .leading)
                            }
                        }
                        if index == 0 { Divider().gridCellColumns(rows.first?.count ?? 2) }
                    }
                }.padding(14)
            }.background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        case .diagram(let source):
            HelpDiagram(source: source).accessibilityIdentifier("helpDiagram")
        case .image(let name, let description):
            if let image = UIImage(named: name) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: name.contains("iphone") ? 460 : 360)
                    .frame(maxWidth: .infinity).accessibilityLabel(description)
            }
        }
    }

    private func richText(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct HelpChapter: Identifiable {
    let id: Int
    let title: String
    let blocks: [HelpBlock]

    static func sections(in blocks: [HelpBlock]) -> [HelpChapter] {
        let starts = blocks.indices.filter { blocks[$0].isSection }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : blocks.count
            return HelpChapter(id: start, title: blocks[start].plainText, blocks: Array(blocks[start..<end]))
        }
    }
}

enum HelpBlock {
    case heading(Int, String), paragraph(String), item(String, String)
    case table([[String]]), diagram(String), image(String, String)

    var plainText: String { if case .heading(_, let text) = self { return text }; return "" }
    var isSection: Bool { if case .heading(2, _) = self { return true }; return false }
    var anchor: String? {
        guard case .heading(_, let text) = self else { return nil }
        return text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.replacingOccurrences(of: " ", with: "-")
    }

    static func parse(_ text: String) -> [HelpBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [HelpBlock] = [], index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty { continue }
            // Language follows the device rather than links in the document.
            if line.hasPrefix("[English]") || line.hasPrefix("[Français]") { continue }
            if line.hasPrefix("```") {
                var content: [String] = []
                while index < lines.count && !lines[index].hasPrefix("```") { content.append(lines[index]); index += 1 }
                index += 1
                if line == "```mermaid" { blocks.append(.diagram(content.joined(separator: "\n"))) }
                continue
            }
            if line.hasPrefix("<img ") {
                let iphone = line.contains("iPhone-")
                let language = line.contains("/fr/") ? "fr" : "en"
                let alt = line.components(separatedBy: "alt=\"").dropFirst().first?.components(separatedBy: "\"").first ?? "CutFuze"
                blocks.append(.image("help-\(iphone ? "iphone" : "ipad")-\(language)", alt))
                continue
            }
            if line.hasPrefix("|") {
                var rows = [line]
                while index < lines.count && lines[index].hasPrefix("|") { rows.append(lines[index]); index += 1 }
                blocks.append(.table(rows.filter { !$0.contains("---") }.map {
                    $0.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
                }))
                continue
            }
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") {
                blocks.append(.item("•", String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), Int(line[..<dot]) != nil {
                blocks.append(.item(String(line[...dot]), String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }
}

/// Native diagrams keep labels readable offline and with Dynamic Type.
private struct HelpDiagram: View {
    let source: String
    private var nodes: [String: String] {
        let regex = try! NSRegularExpression(pattern: #"([A-Z]+)\[([^\]]+)\]"#)
        let string = source as NSString
        return Dictionary(regex.matches(in: source, range: NSRange(location: 0, length: string.length)).map {
            (string.substring(with: $0.range(at: 1)), string.substring(with: $0.range(at: 2)))
        }, uniquingKeysWith: { first, _ in first })
    }
    private var edges: [(String, String, String)] {
        let normalized = source.replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
        var result: [(String, String, String)] = []
        for line in normalized.components(separatedBy: .newlines) where line.contains("-->") {
            let parts = line.components(separatedBy: "-->")
            for index in 1..<parts.count {
                let from = parts[index - 1].trimmingCharacters(in: .whitespaces).components(separatedBy: "|").last ?? ""
                let target = parts[index].trimmingCharacters(in: .whitespaces)
                let fields = target.components(separatedBy: "|")
                result.append((from.trimmingCharacters(in: .whitespaces), (fields.last ?? target).trimmingCharacters(in: .whitespaces), fields.count > 1 ? fields[1] : ""))
            }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isChain, let first = edges.first {
                node(first.0)
                ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down").font(.caption).accessibilityHidden(true)
                        if !edge.2.isEmpty { Text(edge.2).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.leading, 12)
                    node(edge.1)
                }
            } else {
            ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                VStack(alignment: .leading, spacing: 6) {
                    if !edge.2.isEmpty { Text(edge.2).font(.caption).foregroundStyle(.secondary) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { node(edge.0); Image(systemName: "arrow.right"); node(edge.1) }
                        VStack(alignment: .leading, spacing: 8) { node(edge.0); Image(systemName: "arrow.down"); node(edge.1) }
                    }
                }
            }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
    private var isChain: Bool {
        let links = edges
        return !links.isEmpty && (1..<links.count).allSatisfy { links[$0 - 1].1 == links[$0].0 }
    }
    private func node(_ id: String) -> some View {
        Text(nodes[id] ?? id).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 9))
    }
}
