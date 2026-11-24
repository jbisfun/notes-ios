import FossifyCommons
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum MainSheet: Identifiable {
    case newNote(value: String, title: String?, path: String, checklist: Bool)
    case rename(Note)
    case delete(Note)
    case openNote
    case sort(Int64)
    case addItems(Int64)
    case editTask(Int64, TaskItem)
    case lockSetup(Int64)
    case importChoice(url: URL, title: String, content: String, checklist: Bool)
    case exportChoice(url: URL, text: String)
    case importFolder(URL)
    case share(String)

    var id: String {
        switch self {
        case .newNote: return "new"
        case .rename: return "rename"
        case .delete: return "delete"
        case .openNote: return "open"
        case .sort: return "sort"
        case .addItems: return "add"
        case .editTask: return "edit"
        case .lockSetup: return "lock"
        case .importChoice: return "importChoice"
        case .exportChoice: return "exportChoice"
        case .importFolder: return "importFolder"
        case .share: return "share"
        }
    }
}

enum ImporterMode { case file, folder }

/// MainActivity: notes pager, toolbar menu and their dialogs.
struct MainView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.closeApp) private var closeApp
    @Environment(\.scenePhase) private var phase

    @State private var selectedId: Int64 = 0
    @State private var sheet: MainSheet?
    @State private var pending: MainSheet?
    @State private var importer: ImporterMode?
    @State private var exportDocument: TextFile?
    @State private var exportName = ""
    @State private var check: SecurityCheck?
    @State private var confirmUnsaved = false
    @State private var confirmLock = false
    @State private var didStart = false

    private var notes: [Note] { store.notes }
    private var current: Note? { store.note(selectedId) ?? notes.first }
    private var session: NoteSession { store.session(current?.noteId ?? 0) }
    private var isChecklist: Bool { current?.type == .checklist }

    var body: some View {
        VStack(spacing: 0) {
            if isChecklist && !session.selected.isEmpty {
                selectionBar
            } else {
                topBar
            }
            if notes.count > 1 { tabStrip }
            pager
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear(perform: start)
        .onChange(of: selectedId) { old, new in pageChanged(from: old, to: new) }
        // A widget click (OPEN_NOTE_ID) sets the current note while the app is already open.
        .onChange(of: config.currentNoteId) { _, id in
            if id != selectedId && store.note(id) != nil { select(id) }
        }
        .onChange(of: phase) { _, p in
            if p != .active && config.autosaveNotes { store.saveText(selectedId, force: false) }
            if p == .active { store.runAutoBackupIfDue() }
        }
        .onChange(of: router.openURL) { _, url in
            guard let url else { return }
            router.openURL = nil
            importURL(url)
        }
        .onChange(of: store.notes.map(\.id)) { _, ids in
            if !ids.contains(selectedId) { selectedId = ids.first.flatMap { $0 } ?? 0 }
        }
        .sheet(item: $sheet, onDismiss: {
            if let p = pending {
                pending = nil
                sheet = p
            }
        }) { s in sheetView(s).environment(\.palette, palette) }
        .securityCheck($check)
        .fileImporter(isPresented: Binding(get: { importer != nil }, set: { if !$0 { importer = nil } }),
                      allowedContentTypes: importer == .folder ? [.folder] : [.text, .json]) { result in
            let mode = importer
            importer = nil
            guard case .success(let url) = result else { return }
            later { if mode == .folder { sheet = .importFolder(url) } else { importURL(url) } }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .plainText, defaultFilename: exportName) { result in
            let text = exportDocument.map { String(decoding: $0.data, as: UTF8.self) } ?? ""
            exportDocument = nil
            switch result {
            case .success(let url): later { sheet = .exportChoice(url: url, text: text) }
            case .failure(let e): store.toast = e.localizedDescription
            }
        }
        .alert("You have some unsaved changes. What do you want to do with them?", isPresented: $confirmUnsaved) {
            Button("Save") {
                for n in notes { store.saveText(n.noteId, force: false) }
                leave()
            }
            Button("Discard", role: .destructive) { leave() }
        }
        .alert("WARNING: If you forget the notes' password, you won't be able to recover it or access the notes' content anymore.",
               isPresented: $confirmLock) {
            Button("Cancel", role: .cancel) {}
            Button("OK") { if let id = current?.noteId { later { sheet = .lockSetup(id) } } }
        }
    }

    // MARK: Startup and paging

    private func start() {
        guard !didStart else { return }
        didStart = true
        selectedId = store.note(config.currentNoteId) != nil ? config.currentNoteId : (notes.first?.noteId ?? 0)
        if config.showKeyboard, current?.type == .text { session.focusRequest += 1 }
        store.runAutoBackupIfDue()
        if config.showNotePicker && router.openURL == nil { sheet = .openNote }
        if let url = router.openURL {
            router.openURL = nil
            importURL(url)
        }
    }

    private func pageChanged(from old: Int64, to new: Int64) {
        if config.autosaveNotes { store.saveText(old, force: false) }
        store.session(old).selected.removeAll()
        if new != 0 { config.currentNoteId = new }
        if store.note(new)?.type == .checklist { hideKeyboard() }
    }

    private func select(_ id: Int64) {
        withAnimation { selectedId = id }
    }

    private var pager: some View {
        TabView(selection: $selectedId) {
            ForEach(notes, id: \.id) { note in
                page(note).tag(note.noteId)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func page(_ note: Note) -> some View {
        let s = store.session(note.noteId)
        switch note.type {
        case .text:
            TextNotePage(note: note, session: s) { handleUnlocking(note) {} }
        case .checklist:
            ChecklistPage(note: note, session: s, onUnlock: { handleUnlocking(note) {} }) { sheet = .addItems(note.noteId) }
        }
    }

    /// PagerTabStrip: previous / current / next note titles.
    private var tabStrip: some View {
        let index = notes.firstIndex { $0.id == current?.id } ?? 0
        let size = config.percentageFontSize
        return HStack(spacing: 0) {
            Button { if index > 0 { select(notes[index - 1].noteId) } } label: {
                Text(index > 0 ? notes[index - 1].title : "").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(0.4)
            Text(current?.title ?? "")
                .lineLimit(1)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 3) }
                .frame(maxWidth: .infinity)
            Button { if index < notes.count - 1 { select(notes[index + 1].noteId) } } label: {
                Text(index < notes.count - 1 ? notes[index + 1].title : "").lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .opacity(0.4)
        }
        .font(.system(size: size))
        .foregroundStyle(palette.primaryColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: Toolbar (menu.xml)

    private var showSaveButton: Bool {
        !config.autosaveNotes && current?.type == .text && store.hasUnsavedChanges(selectedId)
    }

    private var isDefaultEmptyNote: Bool {
        guard let n = current else { return false }
        return n.title == "General note" && (store.currentText(n.noteId) ?? "").isEmpty && n.value.isEmpty
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            if closeApp != nil {
                IconButton(icon: "square.grid.2x2", action: tryClose)
            }
            Spacer()
            if showSaveButton { IconButton(icon: "square.and.arrow.down") { menu { saveNote() } } }
            if !isChecklist { IconButton(icon: "magnifyingglass") { menu { unlocked { openSearch() } } } }
            if notes.count > 1 { IconButton(icon: "folder") { menu { sheet = .openNote } } }
            IconButton(icon: "plus") { menu { sheet = .newNote(value: "", title: nil, path: "", checklist: false) } }
            if !isChecklist && session.canUndo { IconButton(icon: "arrow.uturn.backward") { undo() } }
            if !isChecklist && session.canRedo { IconButton(icon: "arrow.uturn.forward") { redo() } }
            OverflowMenu { overflowItems }
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    @ViewBuilder
    private var overflowItems: some View {
        if notes.count > 1 {
            Button("Rename note") { menu { unlocked { displayRename() } } }
        }
        if isChecklist {
            Button("Delete checked items") { menu { unlocked { store.removeCheckedItems(session) } } }
            Button("Uncheck all items") { menu { unlocked { store.uncheckAllItems(session) } } }
            Button("Sort by") { menu { unlocked { if let id = current?.noteId { sheet = .sort(id) } } } }
        }
        Button("Share") { menu { unlocked { shareText() } } }
        if let n = current {
            if n.isLocked {
                Button("Unlock note") { menu { unlockNote() } }
            } else {
                Button("Lock note") { menu { confirmLock = true } }
            }
        }
        Button("Open file") { menu { hideKeyboard(); importer = .file } }
        Button("Import folder") { menu { hideKeyboard(); importer = .folder } }
        Button("Export as file") { menu { unlocked { tryExportAsFile() } } }
        Button("Print") { menu { unlocked { printText() } } }
        if !isDefaultEmptyNote || notes.count > 1 {
            Button("Delete note") { menu { unlocked { if let n = current { sheet = .delete(n) } } } }
        }
        Button("Settings") { menu { hideKeyboard(); router.push(.settings) } }
        Button("About") { menu { router.push(.about) } }
    }

    /// Menu clicks save the current note first when autosaving.
    private func menu(_ action: () -> Void) {
        if config.autosaveNotes { store.saveText(selectedId, force: false) }
        action()
    }

    /// CAB of TasksAdapter (cab_checklist.xml).
    private var selectionBar: some View {
        let s = session
        let selectedTasks = s.tasks.filter { s.selected.contains($0.id) }
        let canMove = selectedTasks.allSatisfy { !$0.isDone } || !config.moveDoneChecklistItems
        return ActionModeBar(count: s.selected.count, onClose: { s.selected.removeAll() }) {
            if canMove {
                IconButton(icon: "arrow.up.to.line") { store.moveTasksToTop(s, ids: ordered(selectedTasks)) }
                IconButton(icon: "arrow.down.to.line") { store.moveTasksToBottom(s, ids: ordered(selectedTasks)) }
            }
            if selectedTasks.count == 1, let t = selectedTasks.first {
                IconButton(icon: "pencil") { sheet = .editTask(s.noteId, t) }
            }
            IconButton(icon: "trash") {
                store.deleteTasks(s, ids: s.selected)
                s.selected.removeAll()
            }
        }
    }

    private func ordered(_ tasks: [TaskItem]) -> [Int] { tasks.map(\.id) }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ s: MainSheet) -> some View {
        switch s {
        case let .newNote(value, title, path, checklist):
            NewNoteDialog(title: title, checklistDefault: checklist) { note in
                var n = note
                n.value = value
                n.path = path
                addNewNote(n)
            }
        case .rename(let note):
            RenameNoteDialog(note: note, currentText: store.currentText(note.noteId)) { renamed in
                select(renamed.noteId)
            }
        case .delete(let note):
            DeleteNoteDialog(note: note) { deleteFile in
                if let c = SecurityCheck.deleteProtection({ deleteNote(note, deleteFile: deleteFile) }) {
                    later { check = c }
                } else {
                    deleteNote(note, deleteFile: deleteFile)
                }
            }
        case .openNote:
            OpenNoteDialog(onPick: { select($0) }, onNew: { note in addNewNote(note) })
        case .sort(let id):
            SortChecklistDialog(noteId: id) { store.applySorting(store.session(id)) }
        case .addItems(let id):
            NewChecklistItemDialog(noteId: id) { titles in store.addTasks(store.session(id), titles: titles) }
        case let .editTask(id, task):
            EditTaskDialog(title: task.title) { title in
                let s = store.session(id)
                store.renameTask(s, task, title: title)
                s.selected.removeAll()
            }
        case .lockSetup(let id):
            SecurityDialog(requiredHash: "", showTabIndex: Protection.showAllTabs) { hash, type, ok in
                guard ok, var n = store.note(id) else { return }
                n.protectionHash = hash
                n.protectionType = type
                if n.type == .text, let text = store.currentText(id), config.autosaveNotes { n.value = n.path.isEmpty ? text : n.value }
                store.insertOrUpdate(n)
            }
        case let .importChoice(url, title, content, checklist):
            FileSyncDialog(title: nil, pathHint: nil, path: nil,
                           syncText: "Update the file itself at updating the note\n(note gets deleted if file gets deleted, or path changes)",
                           copyText: "Only import the file content\n(changing the file will not affect the note)") { sync in
                pending = .newNote(value: content, title: title, path: sync ? (FileLink.bookmark(url) ?? "") : "", checklist: checklist)
            }
        case let .exportChoice(url, text):
            FileSyncDialog(title: nil, pathHint: nil, path: nil,
                           syncText: "Update the file itself at updating the note\n(note gets deleted if file gets deleted, or path changes)",
                           copyText: "Only export the current file content\n(changing the note will not affect the file)") { sync in
                exported(url: url, text: text, sync: sync)
            }
        case .share(let text):
            ShareSheet(items: [text])
        case .importFolder(let url):
            FileSyncDialog(title: "Import folder", pathHint: "Folder", path: url.lastPathComponent,
                           syncText: "Update the file itself at updating the note\n(note gets deleted if file gets deleted, or path changes)",
                           copyText: "Only import the file content\n(changing the file will not affect the note)") { sync in
                importFolder(url, sync: sync)
            }
        }
    }

    // MARK: Actions

    /// NoteFragment.handleUnlocking().
    private func unlocked(_ action: @escaping () -> Void) {
        guard let n = current else { return }
        handleUnlocking(n, action)
    }

    private func handleUnlocking(_ note: Note, _ action: @escaping () -> Void) {
        let s = store.session(note.noteId)
        if !note.isLocked || s.unlocked {
            action()
            return
        }
        check = SecurityCheck(protectionType: note.protectionType, requiredHash: note.protectionHash) { _, _ in
            s.unlocked = true
            action()
        }
    }

    private func addNewNote(_ note: Note) {
        let id = store.insertOrUpdate(note)
        select(id)
        if note.type == .text {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.session(id).focusRequest += 1 }
        }
    }

    private func saveNote() {
        store.saveText(selectedId, force: true)
    }

    private func undo() {
        session.textView?.undoManager?.undo()
        session.canUndo = session.textView?.undoManager?.canUndo ?? false
        session.canRedo = session.textView?.undoManager?.canRedo ?? false
    }

    private func redo() {
        session.textView?.undoManager?.redo()
        session.canUndo = session.textView?.undoManager?.canUndo ?? false
        session.canRedo = session.textView?.undoManager?.canRedo ?? false
    }

    /// openSearch(): the system find navigator (search field with previous / next).
    private func openSearch() {
        guard let tv = session.textView else { return }
        tv.becomeFirstResponder()
        tv.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    private func displayRename() {
        guard let n = current else { return }
        sheet = .rename(n)
    }

    private func shareText() {
        guard let n = current else { return }
        let text = n.type == .text ? store.currentText(n.noteId)
            : ((store.storedValue(n) ?? n.value).checklistToPlainText(moveDoneToBottom: config.moveDoneChecklistItems) ?? n.value)
        guard let text, !text.isEmpty else {
            store.toast = "Cannot share empty text"
            return
        }
        sheet = .share(text)
    }

    private func printText() {
        guard let n = current else { return }
        let text = n.type == .text ? (store.currentText(n.noteId) ?? "")
            : store.session(n.noteId).tasks.map { "\($0.title)\n\n" }.joined()
        let info = UIPrintInfo.printInfo()
        info.jobName = n.title
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = UISimpleTextPrintFormatter(text: text)
        controller.present(animated: true)
    }

    /// tryExportAsFile() via the system document picker ("title.txt").
    private func tryExportAsFile() {
        guard let n = current else { return }
        hideKeyboard()
        let value = n.type == .text ? (store.currentText(n.noteId) ?? "") : TaskItem.encode(store.session(n.noteId).tasks)
        exportName = "\(n.title.hasSuffix(".txt") ? String(n.title.dropLast(4)) : n.title).txt"
        exportDocument = TextFile(value)
    }

    /// showExportFilePickUpdateDialog() result.
    private func exported(url: URL, text: String, sync: Bool) {
        guard var n = current else { return }
        if sync, let bookmark = FileLink.bookmark(url) {
            n.path = bookmark
            n.value = ""
        } else {
            n.path = ""
            n.value = text
        }
        store.toast = "Note \"\(n.title)\" exported successfully"
        store.insertOrUpdate(n)
    }

    /// handleUri() / importUri() / addNoteFromUri(): a file picked with "Open file" or opened in the app.
    private func importURL(_ url: URL) {
        if let id = store.noteId(linkedTo: url) {
            select(id)
            return
        }
        let name = url.lastPathComponent
        if name.isMediaFile {
            store.toast = "Invalid file format"
            return
        }
        do {
            let (text, size) = try FileLink.readPicked(url)
            if size > 1000 * 1000 {
                store.toast = "File too large, the limit is 1MB"
                return
            }
            let checklist = text.trimmingCharacters(in: .whitespacesAndNewlines).parseChecklistItems() != nil
            let title = checklist ? (name as NSString).deletingPathExtension : name
            sheet = .importChoice(url: url, title: title, content: checklist ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text,
                                  checklist: checklist)
        } catch {
            store.toast = error.localizedDescription
        }
    }

    /// ImportFolderDialog.saveFolder().
    private func importFolder(_ folder: URL, sync: Bool) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []
        var lastId: Int64?
        for file in files {
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let name = file.lastPathComponent
            if values?.isDirectory == true || name.isMediaFile || (values?.fileSize ?? 0) > 1000 * 1000 || name.hasPrefix(".") { continue }
            if store.noteId(title: name) != nil { continue }
            guard let data = try? Data(contentsOf: file) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.parseChecklistItems() != nil {
                lastId = store.insertOrUpdate(Note(title: (name as NSString).deletingPathExtension, value: trimmed, type: .checklist))
            } else if sync, let bookmark = FileLink.bookmark(file) {
                lastId = store.insertOrUpdate(Note(title: name, type: .text, path: bookmark))
            } else {
                lastId = store.insertOrUpdate(Note(title: name, value: text, type: .text))
            }
        }
        if let lastId, store.note(selectedId) == nil { select(lastId) }
    }

    private func deleteNote(_ note: Note, deleteFile: Bool) {
        let index = notes.firstIndex { $0.id == note.id } ?? 0
        let next: Int64? = notes.count == 1 ? nil : notes[index > 0 ? index - 1 : index + 1].noteId
        if deleteFile {
            do {
                try FileLink.access(note.path) { try FileManager.default.removeItem(at: $0) }
            } catch {
                store.toast = "An unknown error occurred"
            }
        }
        if note.type == .checklist { config.removeOwnSorting(note.noteId) }
        store.delete(note.noteId)
        store.dropSession(note.noteId)
        selectedId = next ?? store.notes.first?.noteId ?? 0
        if store.notes.count == 1 && config.showNotePicker { config.showNotePicker = false }
    }

    private func unlockNote() {
        guard let n = current else { return }
        check = SecurityCheck(protectionType: n.protectionType, requiredHash: n.protectionHash) { _, _ in
            guard var note = store.note(n.noteId) else { return }
            note.protectionHash = ""
            note.protectionType = Protection.none
            store.insertOrUpdate(note)
            store.session(note.noteId).unlocked = true
        }
    }

    /// onBackPressedCompat(): unsaved changes (without autosave) are confirmed before leaving.
    private func tryClose() {
        if !config.autosaveNotes && notes.contains(where: { store.hasUnsavedChanges($0.noteId) }) {
            confirmUnsaved = true
        } else {
            if config.autosaveNotes { store.saveText(selectedId, force: false) }
            leave()
        }
    }

    private func leave() {
        AppLock.shared.lock()
        closeApp?()
    }

    /// Waits for a dismissing sheet / picker / alert before presenting the next one.
    private func later(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: action)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
