import Foundation
import Observation
import TeumCore

@MainActor @Observable
final class LinkedNoteFolders {
    private(set) var folders: [URL]
    private(set) var defaultFolder: URL?
    private(set) var notes: [Note] = []
    private(set) var issues: [String] = []
    private var documents: [UUID: MarkdownFolder.Document] = [:]
    private var ids: [URL: UUID] = [:]
    private var pendingRenames: Set<UUID> = []
    private let configuration: URL
    private let defaultConfiguration: URL
    private let internalFolder: URL
    private let exportHistory: URL

    init(directory: URL) {
        configuration = directory.appendingPathComponent("linked-folders.json")
        defaultConfiguration = directory.appendingPathComponent("default-notes-folder.json")
        internalFolder = directory.appendingPathComponent("Notes", isDirectory: true)
        exportHistory = directory.appendingPathComponent("exported-notes.json")
        do {
            let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: configuration))
            folders = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            folders = []
        } catch {
            folders = []
            issues = ["연결 폴더 설정을 읽지 못했습니다. \(error.localizedDescription)"]
        }
        if let data = try? Data(contentsOf: defaultConfiguration),
           let path = try? JSONDecoder().decode(String.self, from: data) {
            defaultFolder = folders.first { $0.path == path }
        }
    }

    func file(for id: UUID) -> URL? { documents[id]?.url }

    func add(_ folder: URL) throws {
        let folder = folder.resolvingSymlinksInPath()
        guard folder.path != internalFolder.resolvingSymlinksInPath().path else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "이 폴더는 이미 틈노트의 로컬 메모 저장 위치입니다. 다른 폴더를 선택해 주세요."])
        }
        guard !folders.contains(where: { $0.path == folder.path }) else { return }
        try setFolders(folders + [folder])
    }

    func remove(_ folder: URL) throws {
        let path = folder.resolvingSymlinksInPath().path
        if defaultFolder?.path == path {
            try setDefaultFolder(nil)
        }
        try setFolders(folders.filter { $0.path != path })
    }

    func setDefaultFolder(_ folder: URL?) throws {
        let destination = folder?.resolvingSymlinksInPath()
        if let destination { try add(destination) }
        let data = try JSONEncoder().encode(destination?.path)
        try FileManager.default.createDirectory(at: defaultConfiguration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: defaultConfiguration, options: .atomic)
        defaultFolder = destination
    }

    private func setFolders(_ folders: [URL]) throws {
        let data = try JSONEncoder().encode(folders.map(\.path))
        try FileManager.default.createDirectory(at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configuration, options: .atomic)
        self.folders = folders
    }

    func reload(keepingDrafts: Set<UUID> = []) {
        var refreshedNotes: [Note] = []
        var refreshedDocuments: [UUID: MarkdownFolder.Document] = [:]
        var issues: [String] = []
        for folder in folders {
            do {
                for url in try MarkdownFolder.files(in: folder) {
                    let id = ids[url] ?? UUID()
                    ids[url] = id
                    if keepingDrafts.contains(id), let document = documents[id], let note = notes.first(where: { $0.id == id }) {
                        refreshedDocuments[id] = document
                        refreshedNotes.append(note)
                    } else {
                        do {
                            guard let document = try MarkdownFolder.read(url) else {
                                issues.append("\(url.lastPathComponent) · iCloud에서 다운로드 중")
                                continue
                            }
                            refreshedDocuments[id] = document
                            refreshedNotes.append(Note(id: id, text: document.text, updatedAt: document.modifiedAt))
                        } catch {
                            issues.append("\(url.lastPathComponent) · \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                issues.append("\(folder.lastPathComponent) · \(error.localizedDescription)")
            }
        }
        for note in notes where keepingDrafts.contains(note.id) && refreshedDocuments[note.id] == nil {
            refreshedDocuments[note.id] = documents[note.id]
            refreshedNotes.append(note)
        }
        documents = refreshedDocuments
        notes = refreshedNotes
        pendingRenames.formIntersection(refreshedDocuments.keys)
        self.issues = issues
    }

    func update(_ text: String, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
    }

    func updateModifiedAt(_ date: Date, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].updatedAt = date
    }

    func saveBody(_ id: UUID) throws -> Date? {
        guard let original = documents[id], let note = notes.first(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let stem = MarkdownFilename.stem(for: original.text)
        let filename = original.url.lastPathComponent
        let base = original.url.deletingPathExtension().lastPathComponent
        let legacyDraft = base.hasPrefix("새 메모-") && UUID(uuidString: String(base.dropFirst("새 메모-".count))) != nil
        if (legacyDraft || MarkdownFilename.matches(filename, stem: stem) ||
            MarkdownFilename.matches(filename, stem: "새 메모")) &&
            !MarkdownFilename.matches(filename, stem: MarkdownFilename.stem(for: note.text)) {
            pendingRenames.insert(id)
        }
        guard note.text != original.text else { return nil }
        let saved = try MarkdownFolder.save(note.text, replacing: original)
        documents[id] = saved
        return saved.modifiedAt
    }

    func finishTitle(_ id: UUID) throws {
        guard pendingRenames.contains(id), let document = documents[id] else { return }
        let stem = MarkdownFilename.stem(for: document.text)
        if !MarkdownFilename.matches(document.url.lastPathComponent, stem: stem) {
            let destination = try MarkdownFilename.available(in: document.url.deletingLastPathComponent(), stem: stem)
            documents[id] = try MarkdownFolder.move(document, to: destination)
            ids[document.url] = nil
            ids[destination] = id
        }
        pendingRenames.remove(id)
    }

    func archive(_ id: UUID) throws {
        guard let document = documents[id] else { throw CocoaError(.fileNoSuchFile) }
        try MarkdownFolder.archive(document, in: configuration.deletingLastPathComponent())
        documents[id] = nil
        ids[document.url] = nil
        pendingRenames.remove(id)
        notes.removeAll { $0.id == id }
    }

    func restore(_ note: Note, to file: URL) throws {
        let document = try MarkdownFolder.create(note.text, at: file, modifiedAt: note.updatedAt)
        documents[note.id] = document
        ids[file] = note.id
        notes.append(note)
    }

    func addNote(in folder: URL, text: String = "") throws -> UUID {
        let id = UUID()
        let stem = text.isEmpty ? nil : MarkdownFilename.stem(for: text) + " (편집 사본)"
        let document = try MarkdownFilename.create(text, in: folder, stem: stem)
        documents[id] = document
        ids[document.url] = id
        notes.append(Note(id: id, text: text, updatedAt: document.modifiedAt))
        return id
    }

    @discardableResult
    func export(_ notes: [Note], to folder: URL) throws -> (copied: Int, skipped: Int) {
        let key = folder.resolvingSymlinksInPath().path
        var receipts: [String: [UUID: String]]
        do {
            receipts = try JSONDecoder().decode([String: [UUID: String]].self, from: Data(contentsOf: exportHistory))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            receipts = [:]
        }
        let alreadyMapped = Set(receipts[key, default: [:]].values)
        var existing = try MarkdownFolder.files(in: folder).filter { !alreadyMapped.contains($0.lastPathComponent) }
        var copied = 0
        for note in notes where receipts[key]?[note.id] == nil {
            let suffix = "-\(note.id.uuidString).md"
            let stem = MarkdownFilename.stem(for: note.text)
            let match = existing.firstIndex { file in
                file.lastPathComponent.hasSuffix(suffix) ||
                    (MarkdownFilename.matches(file.lastPathComponent, stem: stem) && (try? MarkdownFolder.read(file))?.text == note.text)
            }
            let file: URL
            if let match {
                file = existing.remove(at: match)
            } else {
                file = try MarkdownFilename.create(note.text, in: folder, stem: stem).url
                copied += 1
            }
            receipts[key, default: [:]][note.id] = file.lastPathComponent
            try FileManager.default.createDirectory(at: exportHistory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(receipts).write(to: exportHistory, options: .atomic)
        }
        return (copied, notes.count - copied)
    }
}
