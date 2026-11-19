import AppKit

@MainActor
public enum MarkdownPreviewText {
    private static let blockID = NSAttributedString.Key("TeumPreviewBlock")

    public static func blockRange(at index: Int, in text: NSAttributedString) -> NSRange? {
        guard index >= 0, index < text.length else { return nil }
        var range = NSRange()
        guard text.attribute(blockID, at: index, longestEffectiveRange: &range,
                             in: NSRange(location: 0, length: text.length)) != nil else { return nil }
        return range
    }

    public static func render(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in MarkdownDocument.blocks(in: source).enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
            let start = result.length
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            switch block {
            case .heading(let level, let text):
                style.headerLevel = level
                let sizes: [CGFloat] = [25, 21, 18, 16, 16, 16]
                result.append(inline(text, size: sizes[level - 1], weight: .semibold))
            case .paragraph(let text):
                result.append(inline(text))
            case .listItem(let marker, let text, let indent, let checked):
                let bullet = checked.map { $0 ? "☑" : "☐" } ?? (marker.first?.isNumber == true ? marker : "•")
                style.firstLineHeadIndent = CGFloat(min(indent, 12)) * 6
                style.headIndent = style.firstLineHeadIndent + 18
                result.append(NSAttributedString(string: bullet + " ", attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor]))
                result.append(inline(text))
            case .quote(let text):
                style.firstLineHeadIndent = 12
                style.headIndent = 12
                result.append(inline(text, color: .secondaryLabelColor))
            case .divider:
                result.append(NSAttributedString(string: "────────", attributes: [.foregroundColor: NSColor.separatorColor]))
            case .code(let language, let text):
                if !language.isEmpty {
                    result.append(NSAttributedString(string: language + "\n", attributes: [.font: NSFont.systemFont(ofSize: 10),
                                                                                         .foregroundColor: NSColor.secondaryLabelColor]))
                }
                result.append(NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                                                            .foregroundColor: NSColor.labelColor,
                                                                            .backgroundColor: NSColor.quaternaryLabelColor]))
            }
            let range = NSRange(location: start, length: result.length - start)
            result.addAttributes([.paragraphStyle: style, blockID: index], range: range)
            if case .code(let language, _) = block, !language.isEmpty {
                result.removeAttribute(blockID, range: NSRange(location: start, length: (language as NSString).length + 1))
            }
        }
        return result
    }

    private static func inline(_ source: String, size: CGFloat = 15, weight: NSFont.Weight = .regular,
                               color: NSColor = .labelColor) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}
