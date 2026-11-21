import Foundation
import Testing
import TeumCore

@Test func linkedMarkdownSavesUnicodeAndRejectsStaleEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("메모.md")

    let first = try MarkdownFolder.create("# 한글 👩‍💻\n\n본문", at: url)
    let diskCopy = try MarkdownFolder.read(url)
    let otherMac = try #require(diskCopy)
    let saved = try MarkdownFolder.save("다른 맥에서 저장", replacing: otherMac)

    #expect(throws: MarkdownFolder.FileError.changedOnDisk) {
        try MarkdownFolder.save("오래된 편집", replacing: first)
    }
    #expect(try MarkdownFolder.read(url) == saved)
    #expect(throws: (any Error).self) { try MarkdownFolder.create("중복 복사", at: url) }
    #expect(try MarkdownFolder.read(url)?.text == "다른 맥에서 저장")
}

@Test func linkedFolderListsOnlyDirectMarkdownFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let markdown = directory.appendingPathComponent("a.MARKDOWN")
    let hidden = directory.appendingPathComponent(".hidden.md")
    let text = directory.appendingPathComponent("b.txt")
    let nested = directory.appendingPathComponent("folder.md")
    let symlink = directory.appendingPathComponent("alias.md")
    try MarkdownFolder.create("visible", at: markdown)
    try MarkdownFolder.create("hidden", at: hidden)
    try MarkdownFolder.create("text", at: text)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: markdown)
    #expect(try MarkdownFolder.files(in: directory).map(\.lastPathComponent) == ["a.MARKDOWN"])
}
