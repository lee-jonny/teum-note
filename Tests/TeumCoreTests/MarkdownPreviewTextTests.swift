import AppKit
import Testing
import TeumCore

@Test @MainActor func previewSelectionUsesRenderedMarkdownBlocks() throws {
    let preview = MarkdownPreviewText.render("# 제목\n\n한글 **강조** 👩‍💻\n같은 문단\n\n다음 문단\n\n```swift\n  call()\n    more()\n```")
    let plain = preview.string as NSString
    for (word, expected) in [("같은", "한글 강조 👩‍💻\n같은 문단"), ("more", "  call()\n    more()"), ("다음", "다음 문단")] {
        let range = try #require(MarkdownPreviewText.blockRange(at: plain.range(of: word).location, in: preview))
        #expect(plain.substring(with: range) == expected)
    }
    #expect(MarkdownPreviewText.blockRange(at: plain.length, in: preview) == nil)
}

@Test @MainActor func emptyPreviewHasNoCopyableNoteContent() {
    #expect(MarkdownPreviewText.render("").length == 0)
}

@Test @MainActor func previewCopyOmitsDecorativeDividersButKeepsLiteralCharacters() {
    let preview = MarkdownPreviewText.render("---\n\n첫 문단 👩‍💻\n\n---\n\n둘째 ──────── 문단\n\n---")
    let wholeDocument = NSRange(location: 0, length: preview.length)
    #expect(MarkdownPreviewText.copyText(in: wholeDocument, from: preview) == "첫 문단 👩‍💻\n\n둘째 ──────── 문단")

    let text = preview.string as NSString
    let start = text.range(of: "문단 👩‍💻").location
    let end = NSMaxRange(text.range(of: "둘째"))
    #expect(MarkdownPreviewText.copyText(in: NSRange(location: start, length: end - start), from: preview) == "문단 👩‍💻\n\n둘째")
    #expect(MarkdownPreviewText.copyText(in: text.range(of: "────────"), from: preview).isEmpty)
}
