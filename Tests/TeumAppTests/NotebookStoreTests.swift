import Foundation
import Testing
import TeumCore
@testable import TeumApp

@Test @MainActor func saveConflictDoesNotBlockOtherNotesAndCanBeRecoveredLocally() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    let local = try #require(store.notebook.notes.first)
    let localFile = try #require(store.file(for: local.id))
    try Data("# 로컬 제목\n\n외부 변경".utf8).write(to: localFile, options: .atomic)
    store.updateText("# 로컬 제목\n\n앱에서 변경", id: local.id)

    try store.linkedFolders.setDefaultFolder(fixture.shared)
    let linked = try store.addNote()
    let id = try #require(linked)
    store.updateText("# 클라우드 제목\n\n저장되어야 할 본문", id: id)
    #expect(!store.flush())
    let saved = try #require(store.file(for: id))
    #expect(try MarkdownFolder.read(saved)?.text == "# 클라우드 제목\n\n저장되어야 할 본문")
    #expect(saved.lastPathComponent == "새 메모.md")
    #expect(!store.flush(finishingTitle: id))
    #expect(store.file(for: id)?.lastPathComponent == "클라우드 제목.md")

    store.selectedID = local.id
    #expect(store.canCopyDraft)
    let recovered = try store.saveDraftAsCopy(local.id)
    let copy = try #require(recovered)
    let copyFile = try #require(store.file(for: copy))
    #expect(try MarkdownFolder.read(copyFile)?.text == "# 로컬 제목\n\n앱에서 변경")
    #expect(store.notebook.notes.first?.text == "# 로컬 제목\n\n외부 변경")
    #expect(store.flush())
}

@Test @MainActor func undoAndRedoFollowTheSameOrderAcrossStorageLocations() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    let localNote = try store.addNote()
    let local = try #require(localNote)
    try store.linkedFolders.setDefaultFolder(fixture.shared)
    let linkedNote = try store.addNote()
    let linked = try #require(linkedNote)
    let file = try #require(store.file(for: linked))

    #expect(try store.undoListChange() == .removed(linked))
    #expect(store.file(for: local) != nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try store.redoListChange() == .inserted(linked))
    #expect(FileManager.default.fileExists(atPath: file.path))

    #expect(try store.deleteNote(linked))
    #expect(try store.undoListChange() == .inserted(linked))
    #expect(store.file(for: linked) == file)
}

@Test @MainActor func importingAnEditedOrRenamedCopyAgainDoesNotCreateDuplicates() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    try store.linkedFolders.export(store.notebook.notes, to: fixture.shared)
    let copies = try MarkdownFolder.files(in: fixture.shared)
    let file = try #require(copies.first)
    let remote = try MarkdownFolder.read(file)
    let document = try #require(remote)
    _ = try MarkdownFolder.save("# 다른 제목\n\n사본에서 변경", replacing: document)
    try FileManager.default.moveItem(at: file, to: fixture.shared.appendingPathComponent("변경된 이름.md"))

    let reopened = NotebookStore(fileURL: fixture.legacy)
    try reopened.linkedFolders.export(reopened.notebook.notes, to: fixture.shared)
    #expect(try MarkdownFolder.files(in: fixture.shared).map(\.lastPathComponent) == ["변경된 이름.md"])
}

@Test @MainActor func aDifferentLocalNoteWithTheSameContentCanStillBeCopied() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let folders = fixture.store.linkedFolders
    let first = try #require(fixture.store.notebook.notes.first)
    let second = Note(text: first.text)
    #expect(try folders.export([first], to: fixture.shared).copied == 1)
    #expect(try folders.export([first, second], to: fixture.shared).copied == 1)
    #expect(try MarkdownFolder.files(in: fixture.shared).count == 2)
}

@Test @MainActor func unreadableLocalFileDoesNotHideOtherNotesOrLoseItsMetadata() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    let original = try #require(store.notebook.notes.first)
    let file = try #require(store.file(for: original.id))
    let good = try store.addNote()
    let goodID = try #require(good)
    #expect(store.flush())

    try Data([0xFF, 0xFE, 0xFF]).write(to: file, options: .atomic)
    let partial = NotebookStore(fileURL: fixture.legacy)
    #expect(!partial.loadFailed)
    #expect(partial.notes.map(\.id) == [goodID])
    #expect(partial.localReadIssues.count == 1)
    partial.setEdge(.left)
    #expect(partial.flush())
    try Data(original.text.utf8).write(to: file, options: .atomic)

    let reopened = NotebookStore(fileURL: fixture.legacy)
    #expect(reopened.notes.map(\.id) == [original.id, goodID])
    #expect(reopened.notes.first?.color == original.color)
    #expect(reopened.notebook.edge == .left)
}

@MainActor
private struct StoreFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let shared: URL
    let legacy: URL
    let store: NotebookStore

    init() throws {
        shared = root.appendingPathComponent("Shared", isDirectory: true)
        legacy = root.appendingPathComponent("notes.json")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try NotebookRepository(fileURL: legacy).save(Notebook(notes: [Note(text: "# 로컬 제목\n\n원본", color: .sage)]))
        store = NotebookStore(fileURL: legacy)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
