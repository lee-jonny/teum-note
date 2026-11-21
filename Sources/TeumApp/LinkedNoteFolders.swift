import Foundation
import Observation
import TeumCore

@MainActor @Observable
final class LinkedNoteFolders {
    private(set) var folders: [URL]
    private(set) var notes: [Note] = []
    private(set) var issues: [String] = []
    private var documents: [UUID: MarkdownFolder.Document] = [:]
    private var ids: [URL: UUID] = [:]
    private let configuration: URL

    init(directory: URL) {
        configuration = directory.appendingPathComponent("linked-folders.json")
        do {
            let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: configuration))
            folders = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            folders = []
        } catch {
            folders = []
            issues = ["연결 폴더 설정을 읽지 못했습니다. \(error.localizedDescription)"]
        }
    }

    func file(for id: UUID) -> URL? { documents[id]?.url }

    func add(_ folder: URL) throws {
        let folder = folder.resolvingSymlinksInPath()
        guard !folders.contains(where: { $0.path == folder.path }) else { return }
        try setFolders(folders + [folder])
    }

    func remove(_ folder: URL) throws {
        let path = folder.resolvingSymlinksInPath().path
        try setFolders(folders.filter { $0.path != path })
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
                            refreshedNotes.append(Note(id: id, text: document.text, color: .sky))
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
        self.issues = issues
    }

    func update(_ text: String, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
    }

    func save(_ id: UUID) throws {
        guard let original = documents[id], let note = notes.first(where: { $0.id == id }) else { return }
        documents[id] = try MarkdownFolder.save(note.text, replacing: original)
    }

    func addNote(in folder: URL, text: String = "") throws -> UUID {
        let id = UUID()
        let name = text.isEmpty ? "새 메모" : "편집 사본"
        let url = folder.appendingPathComponent("\(name)-\(id.uuidString).md")
        documents[id] = try MarkdownFolder.create(text, at: url)
        ids[url] = id
        notes.append(Note(id: id, text: text, color: .sky))
        return id
    }

    func export(_ notes: [Note], to folder: URL) throws {
        let existing = try MarkdownFolder.files(in: folder)
        for note in notes {
            let suffix = "-\(note.id.uuidString).md"
            if existing.contains(where: { $0.lastPathComponent.hasSuffix(suffix) }) { continue }
            let title = String(note.title.unicodeScalars.prefix(40))
                .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
                .joined(separator: "-")
            let name = (title.hasPrefix(".") ? "메모 " + title : title) + suffix
            _ = try MarkdownFolder.create(note.text, at: folder.appendingPathComponent(name))
        }
    }
}
