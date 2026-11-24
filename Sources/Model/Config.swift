import Foundation
import Observation

/// SORT_* flags from Fossify Commons.
enum Sort {
    static let descending = 1024
    static let byTitle = 2048
    static let byCustom = 131_072
    static let byDateCreated = 262_144
}

/// GRAVITY_START / CENTER / END.
enum Gravity: Int, CaseIterable {
    case start = 0, center, end

    var title: String {
        switch self {
        case .start: return "Left"
        case .center: return "Center"
        case .end: return "Right"
        }
    }
}

/// Port of the notes Config (SharedPreferences -> UserDefaults); colors live in FossifyCommons.BaseConfig,
/// password protection in FossifyCommons.SecurityConfig. Uses its own suite so the generic keys
/// (sort_order, auto_backup, ...) don't collide with other apps inside the launcher.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults(suiteName: "org.fossify.notes") ?? .standard

    var autosaveNotes: Bool { didSet { d.set(autosaveNotes, forKey: "autosave_notes") } }
    var displaySuccess: Bool { didSet { d.set(displaySuccess, forKey: "display_success") } }
    var clickableLinks: Bool { didSet { d.set(clickableLinks, forKey: "clickable_links") } }
    var monospacedFont: Bool { didSet { d.set(monospacedFont, forKey: "monospaced_font") } }
    var showKeyboard: Bool { didSet { d.set(showKeyboard, forKey: "show_keyboard") } }
    var showNotePicker: Bool { didSet { d.set(showNotePicker, forKey: "show_note_picker") } }
    var showWordCount: Bool { didSet { d.set(showWordCount, forKey: "show_word_count") } }
    var gravity: Gravity { didSet { d.set(gravity.rawValue, forKey: "gravity") } }
    var currentNoteId: Int64 { didSet { d.set(currentNoteId, forKey: "current_note_id") } }
    var placeCursorToEnd: Bool { didSet { d.set(placeCursorToEnd, forKey: "cursor_placement") } }
    var enableLineWrap: Bool { didSet { d.set(enableLineWrap, forKey: "enable_line_wrap") } }
    var lastUsedExtension: String { didSet { d.set(lastUsedExtension, forKey: "last_used_extension") } }
    var useIncognitoMode: Bool { didSet { d.set(useIncognitoMode, forKey: "use_incognito_mode") } }
    var lastCreatedNoteType: Int { didSet { d.set(lastCreatedNoteType, forKey: "last_created_note_type") } }
    var moveDoneChecklistItems: Bool { didSet { d.set(moveDoneChecklistItems, forKey: "move_undone_checklist_items") } }
    var fontSizePercentage: Int { didSet { d.set(fontSizePercentage, forKey: "font_size_percentage") } }
    var addNewChecklistItemsTop: Bool { didSet { d.set(addNewChecklistItemsTop, forKey: "add_new_checklist_items_top") } }
    var sorting: Int { didSet { d.set(sorting, forKey: "sort_order") } }

    // Backups
    var autoBackup: Bool { didSet { d.set(autoBackup, forKey: "auto_backup") } }
    /// Security-scoped bookmark (base64) of the chosen folder; empty = Documents/Backups.
    var autoBackupFolder: String { didSet { d.set(autoBackupFolder, forKey: "auto_backup_folder") } }
    var autoBackupFilename: String { didSet { d.set(autoBackupFilename, forKey: "auto_backup_filename") } }
    /// Milliseconds, like Android.
    var lastAutoBackupTime: Double { didSet { d.set(lastAutoBackupTime, forKey: "last_auto_backup_time") } }

    /// Bumped on per-checklist sorting changes so views re-read `getSorting`.
    var sortingRevision = 0

    private init() {
        autosaveNotes = d.object(forKey: "autosave_notes") as? Bool ?? true
        displaySuccess = d.object(forKey: "display_success") as? Bool ?? false
        clickableLinks = d.object(forKey: "clickable_links") as? Bool ?? false
        monospacedFont = d.object(forKey: "monospaced_font") as? Bool ?? false
        showKeyboard = d.object(forKey: "show_keyboard") as? Bool ?? true
        showNotePicker = d.object(forKey: "show_note_picker") as? Bool ?? false
        showWordCount = d.object(forKey: "show_word_count") as? Bool ?? false
        gravity = Gravity(rawValue: d.object(forKey: "gravity") as? Int ?? 0) ?? .start
        currentNoteId = (d.object(forKey: "current_note_id") as? NSNumber)?.int64Value ?? 1
        placeCursorToEnd = d.object(forKey: "cursor_placement") as? Bool ?? true
        enableLineWrap = d.object(forKey: "enable_line_wrap") as? Bool ?? true
        lastUsedExtension = d.string(forKey: "last_used_extension") ?? "txt"
        useIncognitoMode = d.object(forKey: "use_incognito_mode") as? Bool ?? false
        lastCreatedNoteType = d.object(forKey: "last_created_note_type") as? Int ?? NoteType.text.rawValue
        moveDoneChecklistItems = d.object(forKey: "move_undone_checklist_items") as? Bool ?? true
        fontSizePercentage = d.object(forKey: "font_size_percentage") as? Int ?? 100
        addNewChecklistItemsTop = d.object(forKey: "add_new_checklist_items_top") as? Bool ?? false
        sorting = d.object(forKey: "sort_order") as? Int ?? Sort.byTitle
        autoBackup = d.object(forKey: "auto_backup") as? Bool ?? false
        autoBackupFolder = d.string(forKey: "auto_backup_folder") ?? ""
        autoBackupFilename = d.string(forKey: "auto_backup_filename") ?? ""
        lastAutoBackupTime = d.double(forKey: "last_auto_backup_time")
    }

    /// getPercentageFontSize(): middle_text_size (17) scaled by the font size percentage.
    var percentageFontSize: CGFloat { 17 * CGFloat(fontSizePercentage) / 100 }

    // MARK: per-checklist sorting (BaseConfig folder sorting keyed by the note id)

    private func sortKey(_ noteId: Int64) -> String { "sort_folder_\(noteId)" }

    func getSorting(_ noteId: Int64?) -> Int {
        _ = sortingRevision
        guard let noteId else { return sorting }
        return d.object(forKey: sortKey(noteId)) as? Int ?? sorting
    }

    func hasOwnSorting(_ noteId: Int64?) -> Bool {
        _ = sortingRevision
        guard let noteId else { return false }
        return d.object(forKey: sortKey(noteId)) != nil
    }

    func saveOwnSorting(_ noteId: Int64, _ value: Int) {
        d.set(value, forKey: sortKey(noteId))
        sortingRevision += 1
    }

    func removeOwnSorting(_ noteId: Int64) {
        d.removeObject(forKey: sortKey(noteId))
        sortingRevision += 1
    }
}
