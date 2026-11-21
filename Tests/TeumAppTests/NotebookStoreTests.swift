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
    #expect(reopened.notebook.notes.map(\.id) == [original.id, goodID])
    #expect(reopened.notebook.notes.first?.color == original.color)
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

@Test @MainActor func togglingNoteModeKeepsPerNoteDefaultsAndFinishesEditing() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    let existing = try #require(store.notebook.notes.first)
    store.selectedID = existing.id
    #expect(store.isPreviewing)

    store.toggleNoteMode()
    #expect(!store.isPreviewing)
    store.updateText("# 바뀐 제목\n\n저장할 메모", id: existing.id)
    store.toggleNoteMode()
    #expect(store.isPreviewing)
    let file = try #require(store.file(for: existing.id))
    #expect(file.lastPathComponent == "바뀐 제목.md")
    #expect(try MarkdownFolder.read(file)?.text == "# 바뀐 제목\n\n저장할 메모")

    let created = try store.addNote()
    let blank = try #require(created)
    #expect(store.selectedID == blank)
    #expect(!store.isPreviewing)
    store.toggleNoteMode()
    #expect(store.isPreviewing)
    store.selectedID = existing.id
    #expect(store.isPreviewing)
    store.selectedID = nil
    store.toggleNoteMode()
    #expect(store.isPreviewing)
}

@Test @MainActor func tabOrderUsesFileDatesAndMovesOnlyWhenEditingFinishes() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    let local = try #require(store.notebook.notes.first)
    let localFile = try #require(store.file(for: local.id))
    let old = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: localFile.path)
    let connected = fixture.shared.appendingPathComponent("새 파일.md")
    try MarkdownFolder.create("# 새 파일", at: connected, modifiedAt: newer)
    try store.linkedFolders.add(fixture.shared)

    let reopened = NotebookStore(fileURL: fixture.legacy)
    reopened.reloadFolders()
    let remote = try #require(reopened.linkedFolders.notes.first)
    #expect(reopened.notes.map(\.id) == [local.id, remote.id])
    let color = reopened.displayColor(for: local)
    reopened.selectedID = local.id
    reopened.toggleNoteMode()
    reopened.updateText("# 로컬 제목\n\n바뀐 본문", id: local.id)
    #expect(reopened.flush())
    #expect(reopened.notes.map(\.id) == [local.id, remote.id])
    reopened.toggleNoteMode()
    #expect(reopened.notes.map(\.id) == [remote.id, local.id])
    #expect(reopened.displayColor(for: local) == color)

    let nextLaunch = NotebookStore(fileURL: fixture.legacy)
    nextLaunch.reloadFolders()
    #expect(nextLaunch.notes.last?.id == local.id)
    let added = try nextLaunch.addNote()
    #expect(nextLaunch.notes.last?.id == added)
}

@Test @MainActor func connectedEditDateWaitsForEditingToFinishEvenWhenReloadingFolders() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    let local = try #require(store.notebook.notes.first)
    let remoteFile = fixture.shared.appendingPathComponent("연결 메모.md")
    try MarkdownFolder.create("# 연결 메모", at: remoteFile, modifiedAt: Date(timeIntervalSince1970: 100))
    try store.linkedFolders.add(fixture.shared)
    store.reloadFolders()
    let remote = try #require(store.linkedFolders.notes.first)
    #expect(store.notes.map(\.id) == [remote.id, local.id])

    store.selectedID = remote.id
    store.toggleNoteMode()
    store.updateText("# 연결 메모\n\n본문 추가", id: remote.id)
    #expect(store.flush())
    store.reloadFolders()
    #expect(store.notes.map(\.id) == [remote.id, local.id])
    store.toggleNoteMode()
    #expect(store.notes.map(\.id) == [local.id, remote.id])
}

@Test @MainActor func automaticColorMatchesFilenameAcrossFoldersAndNormalizations() throws {
    let fixture = try StoreFixture()
    defer { fixture.cleanup() }
    let sameName = "로컬 제목.md"
    try MarkdownFolder.create("# 다른 본문", at: fixture.shared.appendingPathComponent(sameName))
    let store = fixture.store
    try store.linkedFolders.add(fixture.shared)
    store.reloadFolders()
    let local = try #require(store.notebook.notes.first)
    let connected = try #require(store.linkedFolders.notes.first)
    #expect(store.displayColor(for: local) == store.displayColor(for: connected))
    #expect(NoteColor.forFilename(sameName) == NoteColor.forFilename(sameName.decomposedStringWithCanonicalMapping))
    #expect(NoteColor.forFilename("test.md") == .lavender)
}
