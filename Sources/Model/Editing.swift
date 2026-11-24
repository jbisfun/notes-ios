import FossifyCommons
import Foundation
import Observation
import UIKit

/// Live state of one page of the pager (TextFragment / TasksFragment).
@MainActor
@Observable
final class NoteSession {
    let noteId: Int64
    var loaded = false
    /// The editor content of a text note.
    var text = ""
    /// Bumped whenever `text` is replaced from outside the editor.
    var textVersion = 0
    var tasks: [TaskItem] = []
    /// CompletedTasks.expanded.
    var expanded = false
    /// NoteFragment.shouldShowLockedContent.
    var unlocked = false
    var canUndo = false
    var canRedo = false
    /// Checklist items selected in the action mode.
    var selected = Set<Int>()
    /// Bumped to give the editor the keyboard (focusEditText / show keyboard on startup).
    var focusRequest = 0
    var focusHandled = 0
    @ObservationIgnored weak var textView: UITextView?

    init(noteId: Int64) {
        self.noteId = noteId
    }
}

extension NotesStore {
    private static var sessionTable = [Int64: NoteSession]()

    func session(_ id: Int64) -> NoteSession {
        if let s = Self.sessionTable[id] { return s }
        let s = NoteSession(noteId: id)
        Self.sessionTable[id] = s
        return s
    }

    func dropSession(_ id: Int64) { Self.sessionTable[id] = nil }

    // MARK: text notes (TextFragment)

    /// setupFragment(): load the stored value; a linked file that can't be read deletes the note.
    func loadText(_ s: NoteSession) {
        guard !s.loaded, let note = note(s.noteId) else { return }
        guard let value = storedValue(note) else {
            delete(s.noteId)
            return
        }
        s.text = value
        s.textVersion += 1
        s.loaded = true
    }

    /// getCurrentNoteViewText().
    func currentText(_ id: Int64) -> String? {
        guard let note = note(id), note.type == .text else { return nil }
        let s = session(id)
        return s.loaded ? s.text : storedValue(note)
    }

    func hasUnsavedChanges(_ id: Int64) -> Bool {
        guard let note = note(id), note.type == .text else { return false }
        let s = session(id)
        return s.loaded && s.text != storedValue(note)
    }

    /// TextFragment.saveText().
    func saveText(_ id: Int64, force: Bool) {
        guard var note = note(id), note.type == .text else { return }
        let s = session(id)
        guard s.loaded else { return }
        if !note.path.isEmpty && FileLink.resolve(note.path) == nil { return }
        let newText = s.text
        if newText != storedValue(note) || force {
            note.value = newText
            saveNoteValue(note, content: newText)
        }
    }

    /// NoteFragment.saveNoteValue().
    @discardableResult
    func saveNoteValue(_ note: Note, content: String) -> Bool {
        if note.path.isEmpty {
            insertOrUpdate(note)
            if Config.shared.displaySuccess { toast = "Note \"\(note.title)\" saved successfully" }
            return true
        }
        return exportToFile(note.path, title: note.title, content: content, showSuccess: Config.shared.displaySuccess)
    }

    /// exportNoteValueToUri().
    @discardableResult
    func exportToFile(_ path: String, title: String, content: String, showSuccess: Bool) -> Bool {
        do {
            try FileLink.write(path, content)
            if showSuccess { toast = "Note \"\(title)\" exported successfully" }
            return true
        } catch {
            toast = error.localizedDescription
            return false
        }
    }

    // MARK: checklists (TasksFragment)

    func loadTasks(_ s: NoteSession) {
        guard let note = note(s.noteId) else { return }
        let stored = storedValue(note) ?? ""
        if let data = stored.data(using: .utf8), let tasks = try? JSONDecoder().decode([TaskItem]?.self, from: data) {
            s.tasks = tasks ?? []
        } else {
            // migrateCheckListOnFailure(): one unchecked item per line.
            s.tasks = stored.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .enumerated().map { TaskItem(id: $0.offset, title: $0.element, isDone: false) }
            saveTasks(s)
        }
        applySorting(s)
        s.loaded = true
    }

    /// setupAdapter(): sort unless the order is custom.
    func applySorting(_ s: NoteSession) {
        let sorting = Config.shared.getSorting(s.noteId)
        if sorting & Sort.byCustom == 0 {
            s.tasks = TaskItem.sorted(s.tasks, sorting: sorting)
        }
    }

    /// TasksFragment.saveNote().
    func saveTasks(_ s: NoteSession) {
        guard var note = note(s.noteId) else { return }
        if !note.path.isEmpty && FileLink.resolve(note.path) == nil { return }
        note.value = TaskItem.encode(s.tasks)
        saveNoteValue(note, content: note.value)
    }

    func addTasks(_ s: NoteSession, titles: [String]) {
        var maxId = s.tasks.map(\.id).max() ?? 0
        var items = [TaskItem]()
        for title in titles {
            for row in title.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !row.isEmpty {
                maxId += 1
                items.append(TaskItem(id: maxId, dateCreated: TaskItem.now(), title: row, isDone: false))
            }
        }
        if Config.shared.addNewChecklistItemsTop {
            s.tasks.insert(contentsOf: items, at: 0)
        } else {
            s.tasks.append(contentsOf: items)
        }
        saveTasks(s)
        applySorting(s)
    }

    func toggleTask(_ s: NoteSession, _ task: TaskItem) {
        guard let i = s.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        s.tasks[i].isDone.toggle()
        saveAndReload(s)
    }

    func renameTask(_ s: NoteSession, _ task: TaskItem, title: String) {
        guard let i = s.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        s.tasks[i].title = title
        saveAndReload(s)
    }

    func deleteTasks(_ s: NoteSession, ids: Set<Int>) {
        s.tasks.removeAll { ids.contains($0.id) }
        saveAndReload(s)
    }

    func removeCheckedItems(_ s: NoteSession) {
        s.tasks.removeAll(where: \.isDone)
        saveAndReload(s)
    }

    func uncheckAllItems(_ s: NoteSession) {
        for i in s.tasks.indices { s.tasks[i].isDone = false }
        saveAndReload(s)
    }

    /// moveTask(): drag & drop among the movable (unchecked, unless checked items stay in place) tasks.
    func moveTask(_ s: NoteSession, from: Int, to: Int) {
        switchToCustomSorting(s.noteId)
        let movable = s.tasks.indices.filter { !Config.shared.moveDoneChecklistItems || !s.tasks[$0].isDone }
        guard from < movable.count, to < movable.count else { return }
        var sub = movable.map { s.tasks[$0] }
        sub.insert(sub.remove(at: from), at: to)
        for (k, i) in movable.enumerated() { s.tasks[i] = sub[k] }
        saveAndReload(s)
    }

    func moveTasksToTop(_ s: NoteSession, ids: [Int]) { moveTasks(s, ids: ids.reversed(), toTop: true) }

    func moveTasksToBottom(_ s: NoteSession, ids: [Int]) { moveTasks(s, ids: ids, toTop: false) }

    private func moveTasks(_ s: NoteSession, ids: [Int], toTop: Bool) {
        switchToCustomSorting(s.noteId)
        for id in ids {
            guard let i = s.tasks.firstIndex(where: { $0.id == id }) else { continue }
            let t = s.tasks.remove(at: i)
            if toTop { s.tasks.insert(t, at: 0) } else { s.tasks.append(t) }
        }
        saveAndReload(s)
    }

    func saveAndReload(_ s: NoteSession) {
        saveTasks(s)
        applySorting(s)
    }

    private func switchToCustomSorting(_ noteId: Int64) {
        let config = Config.shared
        if config.hasOwnSorting(noteId) {
            config.saveOwnSorting(noteId, Sort.byCustom)
        } else {
            config.sorting = Sort.byCustom
            config.sortingRevision += 1
        }
    }

    /// The checklist value of a note, sorted like the list shows it (OpenNoteAdapter.getFormattedValue).
    func displayedTasks(_ note: Note) -> [TaskItem] {
        guard let value = storedValue(note), let data = value.data(using: .utf8),
              var items = (try? JSONDecoder().decode([TaskItem]?.self, from: data)) ?? nil else { return [] }
        let sorting = Config.shared.getSorting(note.id)
        if sorting & Sort.byCustom == 0 { items = TaskItem.sorted(items, sorting: sorting) }
        if Config.shared.moveDoneChecklistItems {
            items = items.filter { !$0.isDone } + items.filter(\.isDone)
        }
        return items
    }
}
