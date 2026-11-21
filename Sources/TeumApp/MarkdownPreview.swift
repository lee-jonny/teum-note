import AppKit
import SwiftUI
import TeumCore

struct MarkdownPreview: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let reader = PreviewTextView()
        reader.isEditable = false
        reader.isSelectable = true
        reader.drawsBackground = false
        reader.isVerticallyResizable = true
        reader.autoresizingMask = [.width]
        reader.textContainer?.widthTracksTextView = true
        reader.textContainerInset = NSSize(width: 0, height: 6)
        reader.setAccessibilityLabel("마크다운 미리보기")
        scroll.documentView = reader
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let reader = scroll.documentView as? PreviewTextView, reader.source != source else { return }
        reader.source = source
        reader.textStorage?.setAttributedString(MarkdownPreviewText.render(source))
        reader.setSelectedRange(NSRange(location: 0, length: 0))
    }
}

private final class PreviewTextView: NSTextView {
    var source: String?

    override func copy(_ sender: Any?) {
        _ = writeSelection(to: .general, types: [.string])
    }

    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string) else { return super.writeSelection(to: pasteboard, types: types) }
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return false }
        let selected = MarkdownPreviewText.copyText(in: range, from: storage)
        guard !selected.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([selected as NSString])
    }

    override func selectionRange(forProposedRange range: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        if granularity == .selectByWord, let storage = textStorage,
           let block = MarkdownPreviewText.blockRange(at: range.location, in: storage),
           NSMaxRange(range) <= NSMaxRange(block) {
            return block
        }
        return super.selectionRange(forProposedRange: range, granularity: granularity)
    }
}
