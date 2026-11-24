import FossifyCommons
import Foundation
import Observation

/// NotesDatabase + NotesHelper: the notes live in Application Support/Notes/notes.json.
@MainActor
@Observable
final class NotesStore {
    /// One store per process, shared by the app and its home-screen widget (launcher-ios).
    static let shared = NotesStore()

    private(set) var notes: [Note] = []
    var toast: String?

    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode([Note].self, from: data) {
            notes = stored
        }
        reload()
    }

    /// NotesHelper.getNotes(): drops notes whose linked file is gone and keeps one "General note".
    func reload() {
        notes.removeAll { !$0.path.isEmpty && FileLink.resolve($0.path) == nil }
        if notes.isEmpty {
            notes = [Note(id: 1, title: "General note", type: .text)]
        }
        // shouldBeUnlocked(): biometric locks can't be opened on a device without biometrics.
        for i in notes.indices where notes[i].shouldBeUnlocked {
            notes[i].protectionType = Protection.none
            notes[i].protectionHash = ""
        }
        sortAndSave()
    }

    private func sortAndSave() {
        notes.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? e.encode(notes) { try? data.write(to: fileURL, options: .atomic) }
    }

    func note(_ id: Int64) -> Note? { notes.first { $0.id == id } }

    /// insertOrUpdate(): returns the note id.
    @discardableResult
    func insertOrUpdate(_ note: Note) -> Int64 {
        var note = note
        if let id = note.id, let i = notes.firstIndex(where: { $0.id == id }) {
            notes[i] = note
        } else {
            if note.id == nil || notes.contains(where: { $0.id == note.id }) {
                note.id = (notes.compactMap(\.id).max() ?? 0) + 1
            }
            notes.append(note)
        }
        sortAndSave()
        return note.noteId
    }

    func delete(_ id: Int64) {
        notes.removeAll { $0.id == id }
        if notes.isEmpty { reload() } else { sortAndSave() }
    }

    /// getNoteIdWithTitle() (COLLATE NOCASE) / getNoteIdWithTitleCaseSensitive().
    func noteId(title: String, caseSensitive: Bool = false) -> Int64? {
        notes.first { caseSensitive ? $0.title == title : $0.title.caseInsensitiveCompare(title) == .orderedSame }?.id
    }

    /// getNoteIdWithPath(): the note already linked with this file.
    func noteId(linkedTo url: URL) -> Int64? {
        let target = url.standardizedFileURL.path
        return notes.first { !$0.path.isEmpty && FileLink.resolve($0.path)?.standardizedFileURL.path == target }?.id
    }

    /// Note.getNoteStoredValue().
    func storedValue(_ note: Note) -> String? {
        note.path.isEmpty ? note.value : FileLink.read(note.path)
    }

    // MARK: import / export (SettingsActivity.importNotes / exportNotes)

    enum ImportResult { case ok, partial, nothingNew, fail }

    func importNotes(_ imported: [Note]) -> ImportResult {
        var added = 0
        for var note in imported {
            if noteId(title: note.title) != nil { continue }
            // Linked file paths from another device can't be resolved here; keep their content.
            if !note.path.isEmpty && FileLink.resolve(note.path) == nil { note.path = "" }
            note.id = notes.contains { $0.id == note.id } ? nil : note.id
            insertOrUpdate(note)
            added += 1
        }
        reload()
        if added == 0 { return .nothingNew }
        return added == imported.count ? .ok : .partial
    }

    static func exportData(_ notes: [Note]) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return (try? e.encode(notes)) ?? Data("[]".utf8)
    }

    // MARK: automatic backups (Context.backupNotes)

    static var defaultBackupFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Backups", isDirectory: true)
    }

    func runAutoBackupIfDue() {
        let config = Config.shared
        guard config.autoBackup else { return }
        let due = AutoBackup.previousBackupTime().timeIntervalSince1970 * 1000
        guard config.lastAutoBackupTime < due else { return }
        backupNotes()
    }

    func backupNotes() {
        let config = Config.shared
        defer { config.lastAutoBackupTime = Date().timeIntervalSince1970 * 1000 }
        let pattern = config.autoBackupFilename.isEmpty ? "Notes_%Y%M%D_%h%m%s" : config.autoBackupFilename
        let filename = AutoBackup.filename(pattern)
        let custom = config.autoBackupFolder.isEmpty ? nil : FileLink.resolve(config.autoBackupFolder)
        let folder = custom ?? Self.defaultBackupFolder
        let scoped = custom?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { custom?.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent("\(filename).json")
            var num = 0
            while FileManager.default.fileExists(atPath: url.path) && !FileManager.default.isWritableFile(atPath: url.path) {
                num += 1
                url = folder.appendingPathComponent("\(filename)_\(num).json")
            }
            try Self.exportData(notes).write(to: url, options: .atomic)
        } catch {
            toast = "Exporting failed"
        }
    }
}

/// Files linked with notes ("Update the file itself at updating the note"): security-scoped bookmarks.
enum FileLink {
    static func bookmark(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))?.base64EncodedString()
    }

    static func resolve(_ path: String) -> URL? {
        guard let data = Data(base64Encoded: path) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func access<T>(_ path: String, _ body: (URL) throws -> T) throws -> T {
        guard let url = resolve(path) else { throw CocoaError(.fileNoSuchFile) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    static func read(_ path: String) -> String? {
        try? access(path) { try String(contentsOf: $0, encoding: .utf8) }
    }

    static func write(_ path: String, _ content: String) throws {
        try access(path) { try content.write(to: $0, atomically: false, encoding: .utf8) }
    }

    static func displayName(_ path: String) -> String {
        resolve(path)?.lastPathComponent ?? ""
    }

    /// Reads a picked/opened file (start access on its security scope).
    static func readPicked(_ url: URL) throws -> (text: String, size: Int) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return (String(decoding: data, as: UTF8.self), data.count)
    }
}
