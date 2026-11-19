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
