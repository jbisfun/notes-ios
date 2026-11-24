import FossifyCommons
import Foundation

/// Publishes the notes for the iOS home-screen note widget (fossify-ios/widgets-ios), which
/// runs in its own process and reads them from the launcher's app group.
public enum NotesWidgetData {
    static let snapshotName = "notes"

    /// Call once at launch (LauncherApp.init): publishes now and after every change.
    @MainActor
    public static func install() {
        WidgetBridge.track { publish() }
    }

    /// `fossify://open/notes?note=<id>` (setupAppOpenIntent's OPEN_NOTE_ID): show that note.
    @MainActor
    public static func handle(_ url: URL) {
        guard let id = WidgetBridge.parse(url)?.query["note"].flatMap(Int64.init), NotesStore.shared.note(id) != nil else { return }
        Config.shared.currentNoteId = id
    }

    @MainActor
    static func publish() {
        let store = NotesStore.shared
        let config = Config.shared
        let notes = store.notes.map { note -> NotesWidgetSnapshot.Note in
            let locked = note.isLocked && !note.shouldBeUnlocked
            let value = locked ? "" : store.storedValue(note) ?? ""
            let tasks = note.type == .checklist && !locked
                ? WidgetSettings.orderedTasks(note, value: value, config: config).map { NotesWidgetSnapshot.Item(title: $0.title, isDone: $0.isDone) }
                : []
            return NotesWidgetSnapshot.Note(id: note.noteId, title: note.title, isChecklist: note.type == .checklist,
                                            isLocked: locked, text: note.type == .checklist ? "" : value, tasks: tasks)
        }
        let snapshot = NotesWidgetSnapshot(notes: notes, gravity: config.gravity.rawValue,
                                           fontSize: Double(config.percentageFontSize), monospaced: config.monospacedFont)
        WidgetBridge.save(snapshot, snapshotName, reload: [WidgetKinds.notes])
        WidgetBridge.publishTheme()
    }
}
