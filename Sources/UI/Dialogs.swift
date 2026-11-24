import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// Material outlined text field used by the dialogs.
struct DialogTextField: View {
    @Environment(\.palette) private var palette
    let hint: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding?
    var incognito = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hint).font(.system(size: 13)).foregroundStyle(palette.primaryColor)
            field
                .font(.system(size: 17))
                .autocorrectionDisabled(incognito)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.primaryColor, lineWidth: 1))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var field: some View {
        if let focused { TextField("", text: $text).focused(focused) } else { TextField("", text: $text) }
    }
}

/// Bottom-right button row with a custom positive action (the dialog validates before dismissing).
struct DialogActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    var negative = "Cancel"
    var positive = "OK"
    let onPositive: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Spacer()
            Button(negative) { dismiss() }
            Button(positive, action: onPositive)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(palette.primaryColor)
        .padding(.top, 16)
    }
}

/// NewNoteDialog.
struct NewNoteDialog: View {
    @Environment(NotesStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    let checklistDefault: Bool
    let onCreate: (Note) -> Void
    @State private var title: String
    @State private var type: NoteType = .text
    @State private var toast: String?
    @FocusState private var focused: Bool

    init(title: String? = nil, checklistDefault: Bool = false, onCreate: @escaping (Note) -> Void) {
        self.checklistDefault = checklistDefault
        self.onCreate = onCreate
        _title = State(initialValue: title ?? "")
    }

    var body: some View {
        DialogFrame(title: "Add a new note") {
            DialogTextField(hint: "Label", text: $title, focused: $focused, incognito: config.useIncognitoMode)
            Text("New note type:").font(.system(size: 14)).padding(.top, 12)
            Button { type = .text } label: { RadioRow(title: "Text note", on: type == .text) }.buttonStyle(.plain)
            Button { type = .checklist } label: { RadioRow(title: "Checklist", on: type == .checklist) }.buttonStyle(.plain)
            DialogActions {
                let t = title.trimmingCharacters(in: .whitespaces)
                if t.isEmpty {
                    toast = "Please name your note"
                } else if store.noteId(title: t) != nil {
                    toast = "A note with that title already exists"
                } else {
                    config.lastCreatedNoteType = type.rawValue
                    dismiss()
                    onCreate(Note(title: t, type: type))
                }
            }
        }
        .toast($toast)
        .onAppear {
            type = checklistDefault || config.lastCreatedNoteType == NoteType.checklist.rawValue ? .checklist : .text
            focused = true
        }
    }
}

/// RenameNoteDialog.
struct RenameNoteDialog: View {
    @Environment(NotesStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    let note: Note
    let currentText: String?
    let onRenamed: (Note) -> Void
    @State private var title: String
    @State private var toast: String?
    @FocusState private var focused: Bool

    init(note: Note, currentText: String?, onRenamed: @escaping (Note) -> Void) {
        self.note = note
        self.currentText = currentText
        self.onRenamed = onRenamed
        _title = State(initialValue: note.title)
    }

    var body: some View {
        DialogFrame(title: "Rename note") {
            DialogTextField(hint: "Title", text: $title, focused: $focused, incognito: config.useIncognitoMode)
            DialogActions(onPositive: confirm)
        }
        .toast($toast)
        .onAppear { focused = true }
    }

    private func confirm() {
        if title.isEmpty {
            toast = "Please name your note"
            return
        }
        if store.noteId(title: title, caseSensitive: true) != nil {
            toast = "A note with that title already exists"
            return
        }
        var renamed = note
        renamed.title = title
        if config.autosaveNotes, let currentText { renamed.value = currentText }
        if !note.path.isEmpty {
            guard title.isAValidFilename else {
                toast = "The name contains invalid characters"
                return
            }
            do {
                let newPath: String? = try FileLink.access(note.path) { url in
                    let target = url.deletingLastPathComponent().appendingPathComponent(title)
                    try FileManager.default.moveItem(at: url, to: target)
                    return FileLink.bookmark(target)
                }
                guard let newPath else { throw CocoaError(.fileWriteUnknown) }
                renamed.path = newPath
            } catch {
                toast = "Could not rename the file"
                return
            }
        }
        store.insertOrUpdate(renamed)
        dismiss()
        onRenamed(renamed)
    }
}

/// DeleteNoteDialog.
struct DeleteNoteDialog: View {
    @Environment(\.dismiss) private var dismiss
    let note: Note
    let onDelete: (Bool) -> Void
    @State private var deleteFile = false

    var body: some View {
        DialogFrame(title: nil) {
            Text("Are you sure you want to delete note \"\(note.title)\"?").font(.system(size: 16))
            if !note.path.isEmpty {
                CheckRow(title: "Also delete file \"\(FileLink.displayName(note.path))\"", on: $deleteFile).padding(.top, 8)
            }
            DialogActions(positive: "Delete") {
                dismiss()
                onDelete(deleteFile && !note.path.isEmpty)
            }
        }
    }
}

/// OpenNoteDialog + OpenNoteAdapter.
struct OpenNoteDialog: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onPick: (Int64) -> Void
    let onNew: (Note) -> Void
    @State private var creating = false

    var body: some View {
        DialogFrame(title: "Open note", scroll: false) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(store.notes, id: \.id) { note in
                        Button {
                            dismiss()
                            onPick(note.noteId)
                        } label: { card(note) }
                            .buttonStyle(PressedStyle())
                    }
                }
                .padding(.bottom, 80)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { creating = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(palette.onPrimary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(palette.primaryColor))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.primaryColor)
            }
            .padding(.top, 8)
        }
        .presentationDetents([.large])
        .sheet(isPresented: $creating) {
            NewNoteDialog { note in
                dismiss()
                onNew(note)
            }
            .environment(\.palette, palette)
        }
    }

    private func card(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if note.isLocked { Image(systemName: "lock").foregroundStyle(palette.primaryColor) }
                Text(note.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.primaryColor)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if !note.path.isEmpty { Image(systemName: "link").foregroundStyle(palette.textColor) }
            }
            if !note.isLocked, let preview = preview(note), !preview.characters.isEmpty {
                Text(preview)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textColor)
                    .lineLimit(8)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.textColor.opacity(0.08)))
    }

    /// getFormattedValue(): text, or "• item" lines with checked items struck through.
    private func preview(_ note: Note) -> AttributedString? {
        switch note.type {
        case .text:
            guard let v = store.storedValue(note), !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return AttributedString(v)
        case .checklist:
            var result = AttributedString()
            for (i, task) in store.displayedTasks(note).enumerated() {
                if i > 0 { result += AttributedString("\n") }
                result += AttributedString("• ")
                var t = AttributedString(task.title)
                if task.isDone { t.strikethroughStyle = .single }
                result += t
            }
            return result
        }
    }
}

/// NewChecklistItemDialog.
struct NewChecklistItemDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let noteId: Int64
    let onAdd: ([String]) -> Void
    @State private var titles = [Row()]
    @State private var addTop = false
    @State private var toast: String?
    @FocusState private var focused: UUID?

    struct Row: Identifiable {
        let id = UUID()
        var text = ""
    }

    var body: some View {
        DialogFrame(title: "Add new checklist items") {
            ForEach($titles) { $row in
                TextField("", text: $row.text, axis: .vertical)
                    .font(.system(size: 17))
                    .autocorrectionDisabled(config.useIncognitoMode)
                    .focused($focused, equals: row.id)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
                    .onChange(of: row.text) { _, text in split(row.id, text) }
            }
            HStack {
                Button { insert(after: titles.last?.id, text: "") } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(palette.onPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(palette.primaryColor))
                }
                Spacer()
            }
            .padding(.top, 12)
            if config.getSorting(noteId) == Sort.byCustom {
                CheckRow(title: "Add to the top", on: $addTop)
            }
            DialogActions {
                config.addNewChecklistItemsTop = addTop
                let list = titles.map(\.text).filter { !$0.isEmpty }
                if list.isEmpty {
                    toast = "Please enter a name"
                } else {
                    dismiss()
                    onAdd(list)
                }
            }
        }
        .interactiveDismissDisabled()
        .toast($toast)
        .onAppear {
            addTop = config.addNewChecklistItemsTop
            focused = titles.first?.id
        }
    }

    /// Enter starts a new item; pasted lines become separate items.
    private func split(_ id: UUID, _ text: String) {
        guard text.contains("\n"), let i = titles.firstIndex(where: { $0.id == id }) else { return }
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        titles[i].text = lines.first ?? ""
        var after = id
        if lines.count <= 1 {
            insert(after: after, text: "")
            return
        }
        for line in lines.dropFirst() { after = insert(after: after, text: line) }
    }

    @discardableResult
    private func insert(after: UUID?, text: String) -> UUID {
        let row = Row(text: text)
        if let after, let i = titles.firstIndex(where: { $0.id == after }) {
            titles.insert(row, at: i + 1)
        } else {
            titles.append(row)
        }
        focused = row.id
        return row.id
    }
}

/// EditTaskDialog.
struct EditTaskDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    let onRename: (String) -> Void
    @State private var title: String
    @State private var toast: String?
    @FocusState private var focused: Bool

    init(title: String, onRename: @escaping (String) -> Void) {
        self.onRename = onRename
        _title = State(initialValue: title)
    }

    var body: some View {
        DialogFrame(title: nil) {
            DialogTextField(hint: "Label", text: $title, focused: $focused, incognito: config.useIncognitoMode)
            DialogActions {
                if title.isEmpty {
                    toast = "Please enter a name"
                } else {
                    dismiss()
                    onRename(title)
                }
            }
        }
        .toast($toast)
        .onAppear { focused = true }
    }
}

/// SortChecklistDialog.
struct SortChecklistDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let noteId: Int64?
    let onSorted: () -> Void
    @State private var field = Sort.byTitle
    @State private var descending = false
    @State private var ownSorting = false

    var body: some View {
        DialogFrame(title: "Sort by") {
            radio("Title", field == Sort.byTitle) { field = Sort.byTitle }
            radio("Date created", field == Sort.byDateCreated) { field = Sort.byDateCreated }
            radio("Custom", field == Sort.byCustom) { field = Sort.byCustom }
            if field != Sort.byCustom {
                Divider().overlay(palette.divider).padding(.vertical, 8)
                radio("Ascending", !descending) { descending = false }
                radio("Descending", descending) { descending = true }
            }
            if noteId != nil {
                Divider().overlay(palette.divider).padding(.vertical, 8)
                CheckRow(title: "Use for this checklist only", on: $ownSorting)
            }
            DialogActions {
                var sorting = field
                if field != Sort.byCustom && descending { sorting |= Sort.descending }
                if ownSorting, let noteId {
                    config.saveOwnSorting(noteId, sorting)
                } else {
                    if let noteId { config.removeOwnSorting(noteId) }
                    config.sorting = sorting
                }
                dismiss()
                onSorted()
            }
        }
        .onAppear {
            let s = config.getSorting(noteId)
            field = s & Sort.byCustom != 0 ? Sort.byCustom : (s & Sort.byDateCreated != 0 ? Sort.byDateCreated : Sort.byTitle)
            descending = s & Sort.descending != 0
            ownSorting = config.hasOwnSorting(noteId)
        }
    }

    private func radio(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { RadioRow(title: title, on: on) }.buttonStyle(.plain)
    }
}

/// OpenFileDialog / ImportFolderDialog / the export sync question: link the note with the file or copy it.
struct FileSyncDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String?
    let pathHint: String?
    let path: String?
    let syncText: String
    let copyText: String
    let onPick: (Bool) -> Void
    @State private var sync = true

    var body: some View {
        DialogFrame(title: title) {
            if let path, let pathHint {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pathHint).font(.system(size: 13)).foregroundStyle(palette.primaryColor)
                    Text(path).font(.system(size: 17)).padding(.vertical, 4)
                }
                .padding(.bottom, 8)
            }
            Button { sync = true } label: { RadioRow(title: syncText, on: sync) }.buttonStyle(.plain)
            Button { sync = false } label: { RadioRow(title: copyText, on: !sync) }.buttonStyle(.plain)
            DialogActions {
                dismiss()
                onPick(sync)
            }
        }
    }
}

/// UnlockNotesDialog: unlock locked notes one by one before exporting them.
struct UnlockNotesDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let notes: [Note]
    let onDone: ([Note]) -> Void
    @State private var unlocked = [Int64]()
    @State private var check: SecurityCheck?

    var body: some View {
        DialogFrame(title: "Unlock notes") {
            Text("The following notes are locked. You can either unlock them one by one or skip exporting them.")
                .font(.system(size: 15))
                .padding(.bottom, 8)
            ForEach(notes, id: \.id) { note in
                let isUnlocked = unlocked.contains(note.noteId)
                Button {
                    if isUnlocked {
                        unlocked.removeAll { $0 == note.noteId }
                    } else {
                        check = SecurityCheck(protectionType: note.protectionType, requiredHash: note.protectionHash) { _, _ in
                            unlocked.append(note.noteId)
                        }
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: isUnlocked ? "lock.open" : "lock").foregroundStyle(isUnlocked ? .green : .red)
                        Text(note.title).foregroundStyle(palette.textColor)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            DialogActions(positive: unlocked.isEmpty ? "Skip" : "OK") {
                dismiss()
                onDone(unlocked.compactMap { id in notes.first { $0.id == id } })
            }
        }
        .interactiveDismissDisabled()
        .securityCheck($check)
    }
}

/// ExportNotesDialog.
struct ExportNotesDialog: View {
    @Environment(\.dismiss) private var dismiss
    let onExport: (String) -> Void
    @State private var filename = "Notes_\(AutoBackup.currentFormattedDateTime())"
    @State private var toast: String?

    var body: some View {
        DialogFrame(title: "Export notes") {
            DialogTextField(hint: "Filename (without .json)", text: $filename)
            DialogActions {
                if filename.isEmpty {
                    toast = "Please enter a name"
                } else if filename.isAValidFilename {
                    dismiss()
                    onExport(filename)
                } else {
                    toast = "The name contains invalid characters"
                }
            }
        }
        .toast($toast)
    }
}

/// ManageAutoBackupsDialog.
struct ManageAutoBackupsDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void
    @State private var folder = ""
    @State private var filename = ""
    @State private var pickFolder = false
    @State private var showInfo = false
    @State private var toast: String?

    var body: some View {
        DialogFrame(title: "Manage automatic backups") {
            Button { pickFolder = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder").font(.system(size: 13)).foregroundStyle(palette.primaryColor)
                    Text(folder.isEmpty ? "Backups" : FileLink.displayName(folder))
                        .font(.system(size: 17))
                        .foregroundStyle(palette.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.primaryColor, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            HStack(alignment: .bottom) {
                DialogTextField(hint: "Filename (without .json)", text: $filename)
                Button { showInfo = true } label: { Image(systemName: "info.circle").font(.system(size: 20)) }
                    .padding(.bottom, 16)
            }
            DialogActions {
                if filename.isEmpty {
                    toast = "Please enter a name"
                } else if filename.isAValidFilename {
                    config.autoBackupFolder = folder
                    config.autoBackupFilename = filename
                    dismiss()
                    onSuccess()
                } else {
                    toast = "The name contains invalid characters"
                }
            }
        }
        .toast($toast)
        .onAppear {
            folder = config.autoBackupFolder
            filename = config.autoBackupFilename.isEmpty ? "Notes_%Y%M%D_%h%m%s" : config.autoBackupFilename
        }
        .sheet(isPresented: $showInfo) { DateTimePatternInfoDialog().environment(\.palette, palette) }
        .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result, let bookmark = FileLink.bookmark(url) { folder = bookmark }
        }
    }
}

/// A plain-text or JSON file for the share/export pickers.
struct TextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    var data: Data

    init(_ text: String) { data = Data(text.utf8) }
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
