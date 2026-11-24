import FossifyCommons
import Foundation

/// models/Widget.kt (the widgets table row) kept per placed widget under `HomeWidgetContext.key(...)`,
/// plus the last used colors (Config.widgetBgColor / widgetTextColor) that seed the next widget.
enum WidgetSettings {
    static let noteIdKey = "note_id"
    static let bgColorKey = "bg_color"
    static let textColorKey = "text_color"
    static let showTitleKey = "show_title"

    /// commons default_widget_bg_color.
    static let defaultBgColor: UInt32 = 0xAA000000
    /// DONE_CHECKLIST_ITEM_ALPHA.
    static let doneAlpha = 0.4

    private static var notesDefaults: UserDefaults { UserDefaults(suiteName: "org.fossify.notes") ?? .standard }

    /// Config.widgetBgColor (last used background, alpha included).
    static var lastBgColor: UInt32 {
        get { (notesDefaults.object(forKey: "widget_bg_color") as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? defaultBgColor }
        set { notesDefaults.set(Int(newValue), forKey: "widget_bg_color") }
    }

    /// Config.widgetTextColor; defaults to the primary color (default_widget_text_color).
    static var lastTextColor: UInt32 {
        get { (notesDefaults.object(forKey: "widget_text_color") as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? BaseConfig.shared.customPrimaryColor }
        set { notesDefaults.set(Int(newValue), forKey: "widget_text_color") }
    }

    /// WidgetAdapter.onDataSetChanged(): the checklist in widget order.
    static func orderedTasks(_ note: Note, value: String, config: Config) -> [TaskItem] {
        let raw = value.isEmpty ? "[]" : value
        var tasks = (try? JSONDecoder().decode([TaskItem].self, from: Data(raw.utf8))) ?? []
        let sorting = config.getSorting(note.noteId)
        if sorting & Sort.byCustom == 0 {
            tasks = TaskItem.sorted(tasks, sorting: sorting)
        }
        if config.moveDoneChecklistItems {
            // sortBy { it.isDone } is stable.
            tasks = tasks.enumerated().sorted { ($0.element.isDone ? 1 : 0, $0.offset) < ($1.element.isDone ? 1 : 0, $1.offset) }.map(\.element)
        }
        return tasks
    }
}
