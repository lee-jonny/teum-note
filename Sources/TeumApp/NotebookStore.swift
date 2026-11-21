import AppKit
import Observation
import TeumCore

struct NoteScrollRequest: Equatable {
    let noteID: UUID
    let token = UUID()
}

@MainActor @Observable
final class NotebookStore {
    var notebook: Notebook
    var selectedID: UUID? {
        didSet {
            if selectedID != oldValue {
                isPreviewing = selectedNote.map { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true
            }
        }
    }
    private(set) var isPreviewing = true
    var hoveredNoteID: UUID?
    var scrollRequest: NoteScrollRequest?
    private(set) var loadFailed = false
    let linkedFolders: LinkedNoteFolders
    private let repository: LocalMarkdownNotebook
    private var pendingSave: Task<Void, Never>?
    private var pendingBodies: Set<UUID> = []
    private var pendingTitles: Set<UUID> = []
    private var savedEditDates: [UUID: Date] = [:]
    private var indexDirty = false
    private var fileErrors: [UUID: String] = [:]
    private var indexError: String?
    private var loadError: String?
    private var listHistory = NoteListHistory()
    private var linkedHistoryPaths: [UUID: URL] = [:]
    private(set) var prefersListUndo = false
    private(set) var prefersListRedo = false

    init(fileURL: URL) {
        repository = LocalMarkdownNotebook(legacyURL: fileURL)
        linkedFolders = LinkedNoteFolders(directory: fileURL.deletingLastPathComponent())
        do {
            notebook = try repository.load()
        } catch {
            notebook = Notebook()
            loadFailed = true
            loadError = "메모를 불러오지 못했습니다. 원본 파일은 보존됩니다.\n\(error.localizedDescription)"
        }
    }

    private var allNotes: [Note] { notebook.notes + linkedFolders.notes }

    var notes: [Note] {
        allNotes.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt < right.updatedAt }
            let leftPath = file(for: left.id)?.path ?? left.id.uuidString
            let rightPath = file(for: right.id)?.path ?? right.id.uuidString
            return leftPath < rightPath
        }
    }

    var selectedNote: Note? { allNotes.first { $0.id == selectedID } }

    func displayColor(for note: Note) -> NoteColor {
        NoteColor.forFilename(file(for: note.id)?.lastPathComponent ?? note.title)
    }
    var localStorageFolder: URL { repository.folder }
    var storageFolder: URL { linkedFolders.defaultFolder ?? localStorageFolder }
    var newNoteLocation: String { linkedFolders.defaultFolder.map(folderLabel) ?? "이 Mac" }
    func file(for id: UUID) -> URL? { linkedFolders.file(for: id) ?? repository.file(for: id) }
    func location(for id: UUID) -> String {
        guard let file = linkedFolders.file(for: id) else { return "이 Mac" }
        return folderLabel(file.deletingLastPathComponent())
    }

    private func folderLabel(_ folder: URL) -> String {
        let name = folder.lastPathComponent
        if name == "com~apple~CloudDocs" { return "iCloud Drive" }
        if folder.pathComponents.contains("com~apple~CloudDocs") {
            return "iCloud Drive › \(name)"
        }
        return name
    }
    var localReadIssues: [String] { repository.issues }
    var errorMessage: String? {
        selectedID.flatMap { fileErrors[$0] } ?? indexError ?? fileErrors.values.sorted().first ?? loadError
    }
    var canUndoListChange: Bool { listHistory.canUndo }
    var canRedoListChange: Bool { listHistory.canRedo }
    var hasUnsavedChanges: Bool {
        indexDirty || !pendingBodies.isEmpty || !pendingTitles.isEmpty
    }
    var canCopyDraft: Bool {
        selectedID.map { fileErrors[$0] != nil && pendingBodies.contains($0) } == true && !loadFailed
    }

    func toggleNoteMode() {
        guard let selectedID, selectedNote != nil else { return }
        if !isPreviewing { flush(finishingTitle: selectedID) }
        isPreviewing.toggle()
    }

    func saveState(for id: UUID) -> String {
        if saveFailed(for: id) { return "저장 실패 · 다시 시도 필요" }
        if pendingBodies.contains(id) { return "저장 중…" }
        return "저장됨"
    }

    func saveFailed(for id: UUID) -> Bool {
        fileErrors[id] != nil || (indexError != nil && linkedFolders.file(for: id) == nil)
    }

    func addNote(in folder: URL? = nil) throws -> UUID? {
        let previousSelection = selectedID
        let index: Int
        let note: Note
        if let destination = folder ?? linkedFolders.defaultFolder {
            index = notes.count
            let id = try linkedFolders.addNote(in: destination)
            guard let created = linkedFolders.notes.first(where: { $0.id == id }) else { return nil }
            note = created
            linkedHistoryPaths[id] = linkedFolders.file(for: id)
        } else {
            guard !loadFailed else { return nil }
            index = notebook.notes.count
            note = Note()
            try repository.create(note)
            notebook.notes.append(note)
            indexDirty = true
            scheduleSave()
        }
        listHistory.recordInsertion(note, at: index, previousSelection: previousSelection)
        selectedID = note.id
        listChangeTookPrecedence(redo: false)
        return note.id
    }

    func reloadFolders() {
        linkedFolders.reload(keepingDrafts: pendingBodies.union(savedEditDates.keys))
    }

    func saveDraftAsCopy(_ id: UUID) throws -> UUID? {
        guard !loadFailed, pendingBodies.contains(id), let draft = notes.first(where: { $0.id == id }) else { return nil }
        let copy = Note(text: draft.text)
        try repository.create(copy)
        let previousSelection = selectedID
        listHistory.recordInsertion(copy, at: notebook.notes.count, previousSelection: previousSelection)
        notebook.notes.append(copy)
        indexDirty = true
        listChangeTookPrecedence(redo: false)
        if linkedFolders.file(for: id) != nil {
            clearPending(id)
            reloadFolders()
        } else {
            // Keep the draft available if the original still cannot be read.
            do {
                if let document = try repository.reloadBody(id),
                   let index = notebook.notes.firstIndex(where: { $0.id == id }) {
                    notebook.notes[index].text = document.text
                    notebook.notes[index].updatedAt = document.modifiedAt
                } else {
                    notebook.notes.removeAll { $0.id == id }
                }
                clearPending(id)
            } catch {
                fileErrors[id] = error.localizedDescription
            }
        }
        _ = flush()
        return copy.id
    }

    func updateText(_ text: String, id: UUID) {
        guard let note = allNotes.first(where: { $0.id == id }), note.text != text else { return }
        if linkedFolders.file(for: id) != nil {
            linkedFolders.update(text, for: id)
        } else if let index = notebook.notes.firstIndex(where: { $0.id == id }) {
            notebook.notes[index].text = text
        } else {
            return
        }
        pendingBodies.insert(id)
        if MarkdownFilename.stem(for: note.text) != MarkdownFilename.stem(for: text) {
            pendingTitles.insert(id)
        }
        listHistory.clearRedo()
        prefersListUndo = false
        prefersListRedo = false
        scheduleSave()
    }

    @discardableResult
    func deleteNote(_ id: UUID) throws -> Bool {
        let previous = notes
        guard let index = previous.firstIndex(where: { $0.id == id }) else { return false }
        let note = previous[index]
        try archive(note)
        listHistory.recordRemoval(note, at: index, previousSelection: selectedID)
        if selectedID == id { selectedID = notes.dropFirst(index).first?.id ?? notes.last?.id }
        listChangeTookPrecedence(redo: false)
        return true
    }

    func undoListChange() throws -> NoteListHistory.Outcome? { try changeList(redo: false) }
    func redoListChange() throws -> NoteListHistory.Outcome? { try changeList(redo: true) }

    private func changeList(redo: Bool) throws -> NoteListHistory.Outcome? {
        let previous = notes
        var candidate = previous
        var history = listHistory
        var selection = selectedID
        let outcome = redo
            ? history.redo(notes: &candidate, selectedID: &selection)
            : history.undo(notes: &candidate, selectedID: &selection)
        guard let outcome else {
            listHistory = history
            return nil
        }
        switch outcome {
        case .removed(let id):
            if let note = previous.first(where: { $0.id == id }) { try archive(note) }
        case .inserted(let id):
            guard let note = candidate.first(where: { $0.id == id }) else { return nil }
            if let file = linkedHistoryPaths[id] {
                let folder = file.deletingLastPathComponent().resolvingSymlinksInPath()
                guard linkedFolders.folders.contains(where: { $0.resolvingSymlinksInPath().path == folder.path }) else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "폴더를 다시 연결한 뒤 실행 취소 또는 다시 실행을 시도해 주세요."])
                }
                try linkedFolders.restore(note, to: file)
            } else {
                try repository.create(note)
                notebook.notes = candidate.filter { linkedFolders.file(for: $0.id) == nil }
                indexDirty = true
                scheduleSave()
            }
        }
        listHistory = history
        selectedID = selection.flatMap { id in notes.contains { $0.id == id } ? id : nil }
        listChangeTookPrecedence(redo: true)
        return outcome
    }

    private func archive(_ note: Note) throws {
        let id = note.id
        if pendingBodies.contains(id) { _ = try saveBody(note) }
        if let file = linkedFolders.file(for: id) {
            try linkedFolders.archive(id)
            linkedHistoryPaths[id] = file
        } else {
            try repository.archive(id)
            notebook.notes.removeAll { $0.id == id }
            indexDirty = true
            scheduleSave()
        }
        clearPending(id)
    }

    private func listChangeTookPrecedence(redo: Bool) {
        prefersListUndo = true
        prefersListRedo = redo
    }

    private func clearPending(_ id: UUID) {
        pendingBodies.remove(id)
        pendingTitles.remove(id)
        savedEditDates[id] = nil
        fileErrors[id] = nil
    }

    func setEdge(_ edge: ScreenEdge) {
        guard !loadFailed else { return }
        notebook.edge = edge
        indexDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flush()
        }
    }

    private func saveBody(_ note: Note) throws -> Date? {
        if linkedFolders.file(for: note.id) != nil {
            try linkedFolders.saveBody(note.id)
        } else {
            try repository.saveBody(note)
        }
    }

    private func publishEditDate(_ date: Date, for id: UUID) {
        if linkedFolders.file(for: id) != nil {
            linkedFolders.updateModifiedAt(date, for: id)
        } else if let index = notebook.notes.firstIndex(where: { $0.id == id }) {
            notebook.notes[index].updatedAt = date
        }
        savedEditDates[id] = nil
    }

    @discardableResult
    func flush(finishingTitle id: UUID? = nil, finishingAllTitles: Bool = false) -> Bool {
        pendingSave?.cancel()
        for note in allNotes where pendingBodies.contains(note.id) {
            do {
                if let date = try saveBody(note) { savedEditDates[note.id] = date }
                pendingBodies.remove(note.id)
                fileErrors[note.id] = nil
            } catch {
                fileErrors[note.id] = error.localizedDescription
            }
        }
        if indexDirty {
            do {
                try repository.saveIndex(notebook)
                indexDirty = false
                indexError = nil
            } catch {
                indexError = error.localizedDescription
            }
        }
        for note in allNotes where pendingTitles.contains(note.id) && (finishingAllTitles || id == note.id) && !pendingBodies.contains(note.id) {
            do {
                if linkedFolders.file(for: note.id) != nil {
                    try linkedFolders.finishTitle(note.id)
                } else {
                    try repository.finishTitle(for: note, in: notebook)
                    if indexDirty {
                        try repository.saveIndex(notebook)
                        indexDirty = false
                        indexError = nil
                    }
                }
                pendingTitles.remove(note.id)
                fileErrors[note.id] = nil
            } catch {
                fileErrors[note.id] = error.localizedDescription
            }
        }
        for (noteID, date) in savedEditDates where (finishingAllTitles || id == noteID) && !pendingBodies.contains(noteID) {
            publishEditDate(date, for: noteID)
        }
        return fileErrors.isEmpty && indexError == nil
    }
}
