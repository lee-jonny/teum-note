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
    var selectedID: UUID?
    var hoveredNoteID: UUID?
    var scrollRequest: NoteScrollRequest?
    var saveState = "이 Mac에 저장됨"
    var errorMessage: String?
    var loadFailed = false
    let linkedFolders: LinkedNoteFolders
    private var pendingFiles: Set<UUID> = []
    private let repository: NotebookRepository
    private var pendingSave: Task<Void, Never>?
    private var dirty = false
    private var listHistory = NoteListHistory()
    private(set) var prefersListUndo = false
    private(set) var prefersListRedo = false

    init(fileURL: URL) {
        repository = NotebookRepository(fileURL: fileURL)
        linkedFolders = LinkedNoteFolders(directory: fileURL.deletingLastPathComponent())
        do {
            if let saved = try repository.load() {
                notebook = saved
            } else {
                notebook = .welcome
                try repository.save(notebook)
            }
        } catch {
            notebook = Notebook()
            loadFailed = true
            errorMessage = "메모를 불러오지 못했습니다. 원본 파일은 보존됩니다.\n\(error.localizedDescription)"
        }
    }

    var notes: [Note] { notebook.notes + linkedFolders.notes }
    var selectedNote: Note? { notes.first { $0.id == selectedID } }
    var fileURL: URL { repository.fileURL }
    var canUndoListChange: Bool { listHistory.canUndo && !loadFailed }
    var canRedoListChange: Bool { listHistory.canRedo && !loadFailed }

    func addNote() -> UUID? {
        guard !loadFailed else { return nil }
        let previousSelection = selectedID
        let note = Note(color: NoteColor.following(notebook.notes.last?.color))
        listHistory.recordInsertion(note, at: notebook.notes.count, previousSelection: previousSelection)
        notebook.notes.append(note)
        selectedID = note.id
        prefersListUndo = true
        prefersListRedo = false
        scheduleSave()
        return note.id
    }

    func reloadFolders() {
        linkedFolders.reload(keepingDrafts: pendingFiles)
    }

    func saveLinkedDraftAsCopy(_ id: UUID) throws -> UUID? {
        guard pendingFiles.contains(id), let file = linkedFolders.file(for: id),
              let note = linkedFolders.notes.first(where: { $0.id == id }) else { return nil }
        let newID = try linkedFolders.addNote(in: file.deletingLastPathComponent(), text: note.text)
        pendingFiles.remove(id)
        if pendingFiles.isEmpty && !dirty {
            saveState = "저장됨"
            errorMessage = nil
        }
        reloadFolders()
        return newID
    }

    var canCopyLinkedDraft: Bool {
        errorMessage != nil && selectedID.map(pendingFiles.contains) == true
    }

    var hasUnsavedChanges: Bool { dirty || !pendingFiles.isEmpty }

    func updateText(_ text: String, id: UUID) {
        if linkedFolders.file(for: id) != nil {
            linkedFolders.update(text, for: id)
            pendingFiles.insert(id)
            prefersListUndo = false
            prefersListRedo = false
            scheduleSave(local: false)
            return
        }
        guard let index = notebook.notes.firstIndex(where: { $0.id == id }) else { return }
        notebook.notes[index].text = text
        notebook.notes[index].updatedAt = .now
        listHistory.clearRedo()
        prefersListUndo = false
        prefersListRedo = false
        scheduleSave()
    }

    func updateColor(_ color: NoteColor, id: UUID) {
        guard let index = notebook.notes.firstIndex(where: { $0.id == id }) else { return }
        notebook.notes[index].color = color
        listHistory.clearRedo()
        prefersListUndo = false
        prefersListRedo = false
        scheduleSave()
    }

    @discardableResult
    func deleteNote(_ id: UUID) -> Bool {
        guard !loadFailed, let index = notebook.notes.firstIndex(where: { $0.id == id }) else { return false }
        let previousSelection = selectedID
        listHistory.recordRemoval(notebook.notes[index], at: index, previousSelection: previousSelection)
        notebook.notes.remove(at: index)
        if previousSelection == id {
            selectedID = index < notebook.notes.count ? notebook.notes[index].id : notes.last?.id
        }
        prefersListUndo = true
        prefersListRedo = false
        scheduleSave()
        return true
    }

    func undoListChange() -> NoteListHistory.Outcome? {
        guard !loadFailed, let outcome = listHistory.undo(notes: &notebook.notes, selectedID: &selectedID) else { return nil }
        prefersListUndo = true
        prefersListRedo = true
        scheduleSave()
        return outcome
    }

    func redoListChange() -> NoteListHistory.Outcome? {
        guard !loadFailed, let outcome = listHistory.redo(notes: &notebook.notes, selectedID: &selectedID) else { return nil }
        prefersListUndo = true
        prefersListRedo = true
        scheduleSave()
        return outcome
    }

    func setEdge(_ edge: ScreenEdge) {
        guard !loadFailed else { return }
        notebook.edge = edge
        scheduleSave()
    }

    private func scheduleSave(local: Bool = true) {
        if local { dirty = true }
        saveState = "저장 중…"
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.flush()
        }
    }

    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        guard dirty || !pendingFiles.isEmpty else { return !loadFailed }
        do {
            if dirty {
                try repository.save(notebook)
                dirty = false
            }
            for id in Array(pendingFiles) {
                try linkedFolders.save(id)
                pendingFiles.remove(id)
            }
            saveState = "저장됨"
            errorMessage = nil
            return true
        } catch {
            saveState = "저장 실패 · 다시 시도 필요"
            errorMessage = "메모를 저장하지 못했습니다.\n\(error.localizedDescription)"
            return false
        }
    }
}
