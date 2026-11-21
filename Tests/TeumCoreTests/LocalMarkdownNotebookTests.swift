import Foundation
import Testing
import TeumCore

@Test func legacyNotebookMigratesToIndependentMarkdownWithoutChangingBackup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = NotebookRepository(fileURL: root.appendingPathComponent("notes.json"))
    let first = Note(text: "# 한글 👩‍💻\n\n**본문**\n", color: .sage)
    let second = Note(text: "다른 메모", color: .sky)
    try legacy.save(Notebook(notes: [first, second], edge: .left))
    let original = try Data(contentsOf: legacy.fileURL)
    let repository = LocalMarkdownNotebook(legacyURL: legacy.fileURL)
    var migrated = try repository.load()
    let firstFile = try #require(repository.file(for: first.id))
    let secondFile = try #require(repository.file(for: second.id))
    let metadata = root.appendingPathComponent("note-index.json")
    let originalIndex = try Data(contentsOf: metadata)

    #expect(firstFile.lastPathComponent == "한글 👩‍💻.md")
    #expect(try String(contentsOf: firstFile, encoding: .utf8) == first.text)
    #expect(try String(contentsOf: secondFile, encoding: .utf8) == second.text)
    migrated.notes[0].text = "# 한글 👩‍💻\n\n새 내용"
    try repository.saveBody(migrated.notes[0])
    #expect(try Data(contentsOf: metadata) == originalIndex)
    #expect(try Data(contentsOf: legacy.fileURL) == original)
    #expect(try String(contentsOf: secondFile, encoding: .utf8) == second.text)

    let reopened = try LocalMarkdownNotebook(legacyURL: legacy.fileURL).load()
    #expect(reopened.edge == .left)
    #expect(reopened.notes.map(\.id) == [first.id, second.id])
    #expect(reopened.notes.map(\.color) == [.sage, .sky])
    #expect(reopened.notes.map(\.text) == [migrated.notes[0].text, second.text])
}

@Test func localMarkdownDeletionAndRestoreKeepFileContents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyURL = root.appendingPathComponent("notes.json")
    let local = LocalMarkdownNotebook(legacyURL: legacyURL)
    let original = try local.load()
    let removed = try #require(original.notes.first)
    let file = try #require(local.file(for: removed.id))
    try local.archive(removed.id)
    try local.saveIndex(Notebook(notes: Array(original.notes.dropFirst())))
    #expect(!FileManager.default.fileExists(atPath: file.path))
    let archive = root.appendingPathComponent("Recently Deleted", isDirectory: true)
    let copies = try MarkdownFolder.files(in: archive)
    #expect(copies.count == 1)
    let copy = try #require(copies.first)
    #expect(try MarkdownFolder.read(copy)?.text == removed.text)

    try local.create(removed)
    try local.saveIndex(original)
    let reopened = try LocalMarkdownNotebook(legacyURL: legacyURL).load()
    #expect(reopened.notes.map(\.id) == original.notes.map(\.id))
    #expect(try String(contentsOf: file, encoding: .utf8) == removed.text)
}

@Test func interruptedMigrationReusesExistingMarkdownRatherThanOverwriting() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = NotebookRepository(fileURL: root.appendingPathComponent("notes.json"))
    let note = Note(text: "기존 JSON")
    try legacy.save(Notebook(notes: [note]))
    let file = root.appendingPathComponent("Notes", isDirectory: true).appendingPathComponent(note.id.uuidString + ".md")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try MarkdownFolder.create("이미 생성된 Markdown", at: file)

    let migrated = try LocalMarkdownNotebook(legacyURL: legacy.fileURL).load()
    #expect(migrated.notes.map(\.text) == ["이미 생성된 Markdown"])
    #expect(try legacy.load()?.notes.first?.text == note.text)
}

@Test func localFilenameChangesWithTitleAndAvoidsCollisions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = NotebookRepository(fileURL: root.appendingPathComponent("notes.json"))
    let first = Note(text: "# 회의: 팀/업무\n\n첫 메모")
    let second = Note(text: "**회의: 팀/업무**\n\n둘째 메모")
    try legacy.save(Notebook(notes: [first, second]))
    let repository = LocalMarkdownNotebook(legacyURL: legacy.fileURL)
    var noteBook = try repository.load()
    #expect(repository.file(for: first.id)?.lastPathComponent == "회의- 팀-업무.md")
    #expect(repository.file(for: second.id)?.lastPathComponent == "회의- 팀-업무 (2).md")

    noteBook.notes[0].text = "# 새 제목\n\n첫 메모"
    try repository.saveBody(noteBook.notes[0])
    #expect(repository.file(for: first.id)?.lastPathComponent == "회의- 팀-업무.md")
    try repository.finishTitle(for: noteBook.notes[0], in: noteBook)
    #expect(repository.file(for: first.id)?.lastPathComponent == "새 제목.md")
    #expect(repository.file(for: second.id)?.lastPathComponent == "회의- 팀-업무 (2).md")
    let reopened = try LocalMarkdownNotebook(legacyURL: legacy.fileURL).load()
    #expect(reopened.notes.map(\.id) == [first.id, second.id])
    #expect(reopened.notes.map(\.text) == noteBook.notes.map(\.text))
}

@Test func openingAfterAnInterruptedRenameKeepsTheIndexedNote() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("notes.json")
    let repository = LocalMarkdownNotebook(legacyURL: legacy)
    let notebook = try repository.load()
    let first = try #require(notebook.notes.first)
    let source = try #require(repository.file(for: first.id))
    let destination = repository.folder.appendingPathComponent("새 이름.md")
    let index = root.appendingPathComponent("note-index.json")

    var checkpoint = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
    checkpoint["pendingRename"] = ["id": first.id.uuidString, "destination": destination.lastPathComponent]
    try JSONSerialization.data(withJSONObject: checkpoint).write(to: index)
    try Data("# 새 이름\n\n변경된 내용".utf8).write(to: source, options: .atomic)
    try FileManager.default.moveItem(at: source, to: destination)

    let reopened = LocalMarkdownNotebook(legacyURL: legacy)
    let recovered = try reopened.load()
    #expect(recovered.notes.first?.id == first.id)
    #expect(recovered.notes.first?.color == first.color)
    #expect(recovered.notes.first?.text == "# 새 이름\n\n변경된 내용")
    #expect(reopened.file(for: first.id)?.lastPathComponent == destination.lastPathComponent)
    #expect(recovered.notes.count == notebook.notes.count)
}
