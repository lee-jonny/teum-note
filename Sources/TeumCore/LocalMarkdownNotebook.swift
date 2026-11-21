import Foundation

/// The local index keeps stable note identifiers. Markdown files own the note bodies and modification dates.
public final class LocalMarkdownNotebook {
    private struct Entry: Codable, Equatable {
        var id: UUID
        // Older builds still expect this field when reopening the index.
        var color: NoteColor
        var filename: String?

        var documentName: String { filename ?? id.uuidString + ".md" }
    }

    private struct Rename: Codable, Equatable {
        var id: UUID
        var destination: String
    }

    private struct Index: Codable, Equatable {
        var edge: ScreenEdge
        var order: [Entry]
        var pendingRename: Rename?
    }

    public let folder: URL
    public private(set) var issues: [String] = []
    private let indexURL: URL
    private let legacy: NotebookRepository
    private var documents: [UUID: MarkdownFolder.Document] = [:]
    private var savedIndex: Index?
    private var unreadableNames: Set<String> = []

    public init(legacyURL: URL) {
        let directory = legacyURL.deletingLastPathComponent()
        folder = directory.appendingPathComponent("Notes", isDirectory: true)
        indexURL = directory.appendingPathComponent("note-index.json")
        legacy = NotebookRepository(fileURL: legacyURL)
    }

    public func file(for id: UUID) -> URL? {
        documents[id]?.url
    }

    public func create(_ note: Note) throws {
        documents[note.id] = try MarkdownFilename.create(note.text, in: folder, modifiedAt: note.updatedAt)
    }

    public func load() throws -> Notebook {
        var index: Index?
        do {
            index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            index = nil
        }

        if index == nil || index?.order.isEmpty == true {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let files = try MarkdownFolder.files(in: folder)
        savedIndex = index

        // The recorded rename may have finished before the final index write.
        if let rename = index?.pendingRename,
           let offset = index?.order.firstIndex(where: { $0.id == rename.id }),
           let entry = index?.order[offset],
           !files.contains(where: { $0.lastPathComponent == entry.documentName }),
           files.contains(where: { $0.lastPathComponent == rename.destination }) {
            index?.order[offset].filename = rename.destination
        }

        documents = try readDocuments(files, index: index)
        var notebook: Notebook
        if let index {
            let notes = index.order.compactMap { entry in
                documents[entry.id].map { Note(id: entry.id, text: $0.text, color: entry.color, updatedAt: $0.modifiedAt) }
            }
            notebook = Notebook(notes: notes, edge: index.edge)
        } else {
            notebook = try legacy.load() ?? (files.isEmpty ? .welcome : Notebook())
            for offset in notebook.notes.indices {
                let id = notebook.notes[offset].id
                if let document = documents[id] {
                    notebook.notes[offset].text = document.text
                    notebook.notes[offset].updatedAt = document.modifiedAt
                }
            }
        }
        appendUnlistedNotes(to: &notebook.notes)
        for note in notebook.notes where documents[note.id] == nil {
            // The UUID lets a partial legacy migration resume before the first index write.
            let file = folder.appendingPathComponent(note.id.uuidString + ".md")
            documents[note.id] = try MarkdownFolder.create(note.text, at: file, modifiedAt: note.updatedAt)
        }
        try saveIndex(notebook)
        for note in notebook.notes {
            do {
                try finishTitle(for: note, in: notebook)
            } catch {
                let name = file(for: note.id)?.lastPathComponent ?? note.title
                issues.append("\(name) · \(error.localizedDescription)")
            }
        }
        return notebook
    }

    @discardableResult
    public func saveBody(_ note: Note) throws -> Date? {
        guard let document = documents[note.id] else { throw CocoaError(.fileNoSuchFile) }
        guard note.text != document.text else { return nil }
        let saved = try MarkdownFolder.save(note.text, replacing: document)
        documents[note.id] = saved
        return saved.modifiedAt
    }

    public func archive(_ id: UUID) throws {
        guard let document = documents[id] else { throw CocoaError(.fileNoSuchFile) }
        try MarkdownFolder.archive(document, in: folder.deletingLastPathComponent())
        documents[id] = nil
    }

    public func reloadBody(_ id: UUID) throws -> MarkdownFolder.Document? {
        guard let file = file(for: id) else { return nil }
        if !FileManager.default.fileExists(atPath: file.path) {
            documents[id] = nil
            return nil
        }
        guard let document = try MarkdownFolder.read(file) else { throw CocoaError(.fileReadUnknown) }
        documents[id] = document
        return document
    }

    public func saveIndex(_ notebook: Notebook) throws {
        try writeIndex(makeIndex(notebook))
    }

    public func finishTitle(for note: Note, in notebook: Notebook) throws {
        guard let file = documents[note.id] else { throw CocoaError(.fileNoSuchFile) }
        let stem = MarkdownFilename.stem(for: file.text)
        if MarkdownFilename.matches(file.url.lastPathComponent, stem: stem) {
            if savedIndex?.pendingRename?.id == note.id { try saveIndex(notebook) }
            return
        }
        let destination = try MarkdownFilename.available(in: folder, stem: stem)
        var index = makeIndex(notebook)
        index.pendingRename = Rename(id: note.id, destination: destination.lastPathComponent)
        try writeIndex(index)
        documents[note.id] = try MarkdownFolder.move(file, to: destination)
        try saveIndex(notebook)
    }

    private func makeIndex(_ notebook: Notebook) -> Index {
        var order = notebook.notes.compactMap { note in
            documents[note.id].map { Entry(id: note.id, color: note.color, filename: $0.url.lastPathComponent) }
        }
        for (offset, entry) in (savedIndex?.order ?? []).enumerated()
            where unreadableNames.contains(entry.documentName) && !order.contains(where: { $0.id == entry.id }) {
            order.insert(entry, at: min(offset, order.count))
        }
        return Index(edge: notebook.edge, order: order)
    }

    private func writeIndex(_ index: Index) throws {
        guard index != savedIndex else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
        savedIndex = index
    }

    private func readDocuments(_ files: [URL], index: Index?) throws -> [UUID: MarkdownFolder.Document] {
        let entries = index?.order ?? []
        guard Set(entries.map(\.id)).count == entries.count,
              Set(entries.map(\.documentName)).count == entries.count else {
            throw NotebookRepository.RepositoryError.duplicateIdentifiers
        }

        let indexedIDs = Dictionary(uniqueKeysWithValues: entries.map { ($0.documentName, $0.id) })
        var result: [UUID: MarkdownFolder.Document] = [:]
        for url in files {
            let filename = url.lastPathComponent
            let id = indexedIDs[filename] ?? UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            guard result[id] == nil else { throw NotebookRepository.RepositoryError.duplicateIdentifiers }
            do {
                guard let document = try MarkdownFolder.read(url) else { throw CocoaError(.fileReadUnknown) }
                result[id] = document
            } catch {
                unreadableNames.insert(filename)
                issues.append("\(filename) · \(error.localizedDescription)")
            }
        }
        return result
    }

    private func appendUnlistedNotes(to notes: inout [Note]) {
        let listed = Set(notes.map(\.id))
        for id in documents.keys.sorted(by: { $0.uuidString < $1.uuidString }) where !listed.contains(id) {
            if let document = documents[id] {
                notes.append(Note(id: id, text: document.text, updatedAt: document.modifiedAt))
            }
        }
    }
}
