import FossifyCommons
import SwiftUI

/// Fossify Notes' home-screen widget (MyWidgetProvider + WidgetService/WidgetAdapter + WidgetConfigureActivity)
/// for launcher-ios: one note, text or checklist, on a rounded colored background.
public enum NotesWidgets {
    public static let all: [HomeWidgetKind] = [
        // widget_info.xml: targetCell 2x2, minResize 40dp (1 cell), resizeMode horizontal|vertical.
        HomeWidgetKind(
            id: "notes.note",
            title: "Note",
            defaultSize: CGSize(width: 2, height: 2),
            minSize: CGSize(width: 1, height: 1),
            resizable: true,
            configure: { context, done in AnyView(NoteWidgetConfigureView(context: context, done: done).fossifyTheme()) },
            content: { context in AnyView(NoteWidgetView(context: context)) }
        ),
    ]
}

// MARK: - Widget (MyWidgetProvider.onUpdate)

struct NoteWidgetView: View {
    let context: HomeWidgetContext
    @AppStorage private var noteId: Int
    @AppStorage private var bgColor: Int
    @AppStorage private var textColor: Int
    @AppStorage private var showTitle: Bool

    init(context: HomeWidgetContext) {
        self.context = context
        _noteId = AppStorage(wrappedValue: 0, context.key(WidgetSettings.noteIdKey))
        _bgColor = AppStorage(wrappedValue: Int(WidgetSettings.lastBgColor), context.key(WidgetSettings.bgColorKey))
        _textColor = AppStorage(wrappedValue: Int(WidgetSettings.lastTextColor), context.key(WidgetSettings.textColorKey))
        _showTitle = AppStorage(wrappedValue: false, context.key(WidgetSettings.showTitleKey))
    }

    var body: some View {
        let store = NotesStore.shared
        let note = store.note(Int64(noteId))
        NoteWidgetBody(note: note, value: note.flatMap { store.storedValue($0) } ?? "",
                       bgColor: UInt32(truncatingIfNeeded: bgColor), textColor: UInt32(truncatingIfNeeded: textColor),
                       showTitle: showTitle, config: Config.shared)
            .contentShape(Rectangle())
            .onTapGesture {
                // setupAppOpenIntent(): launch the app with OPEN_NOTE_ID.
                if let id = note?.id { Config.shared.currentNoteId = id }
                context.openApp(nil)
            }
    }
}

/// widget.xml (rounded background, optional one-line title) + the list of widget_text_layout /
/// item_checklist_widget rows.
struct NoteWidgetBody: View {
    let note: Note?
    let value: String
    let bgColor: UInt32
    let textColor: UInt32
    let showTitle: Bool
    let config: Config

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 0) {
            if showTitle {
                Text(note?.title ?? "")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(2)
                    .foregroundStyle(Color(argb: textColor))
            }
            ScrollView {
                if let note {
                    if note.type == .checklist {
                        checklist(WidgetSettings.orderedTasks(note, value: value, config: config))
                    } else {
                        textNote(value)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(Color(argb: bgColor)))
        .clipShape(shape)
    }

    private var alignment: Alignment { [.leading, .center, .trailing][config.gravity.rawValue] }
    private var textAlignment: TextAlignment { [.leading, .center, .trailing][config.gravity.rawValue] }
    private var font: Font {
        config.monospacedFont ? .system(size: config.percentageFontSize, design: .monospaced) : .system(size: config.percentageFontSize)
    }

    private func textNote(_ text: String) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color(argb: textColor))
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(4)   // small_margin
            .padding(12)  // normal_margin
    }

    private func checklist(_ tasks: [TaskItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                Text(task.title)
                    .font(font)
                    .strikethrough(task.isDone)
                    .foregroundStyle(Color(argb: textColor).opacity(task.isDone ? WidgetSettings.doneAlpha : 1))
                    .multilineTextAlignment(textAlignment)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .padding(.leading, 16)
                    .padding([.top, .bottom, .trailing], 8)
            }
        }
    }
}

// MARK: - Configure screen (WidgetConfigureActivity)

private enum ConfigSheet: String, Identifiable {
    case bgColor, textColor, note
    var id: String { rawValue }
}

struct NoteWidgetConfigureView: View {
    let context: HomeWidgetContext
    let done: (Bool) -> Void

    @Environment(\.palette) private var palette
    @State private var bgColorWithoutTransparency: UInt32
    @State private var bgAlpha: Double
    @State private var textColor: UInt32
    @State private var showTitle: Bool
    @State private var currentNoteId: Int64
    @State private var sheet: ConfigSheet?
    @State private var check: SecurityCheck?
    @State private var didStart = false

    private let store = NotesStore.shared
    private let isReconfiguring: Bool

    init(context: HomeWidgetContext, done: @escaping (Bool) -> Void) {
        self.context = context
        self.done = done
        let d = UserDefaults.standard
        func color(_ name: String) -> UInt32? {
            (d.object(forKey: context.key(name)) as? Int).map { UInt32(truncatingIfNeeded: $0) }
        }
        // initVariables(): a placed widget keeps its own values, a new one starts from the last used colors.
        isReconfiguring = d.object(forKey: context.key(WidgetSettings.noteIdKey)) != nil
        let bg = color(WidgetSettings.bgColorKey) ?? WidgetSettings.lastBgColor
        _bgColorWithoutTransparency = State(initialValue: bg | 0xFF000000)
        _bgAlpha = State(initialValue: Double((bg >> 24) & 0xFF) / 255)
        _textColor = State(initialValue: color(WidgetSettings.textColorKey) ?? WidgetSettings.lastTextColor)
        _showTitle = State(initialValue: d.bool(forKey: context.key(WidgetSettings.showTitleKey)))
        _currentNoteId = State(initialValue: (d.object(forKey: context.key(WidgetSettings.noteIdKey)) as? Int).map(Int64.init) ?? 0)
    }

    /// mBgColor = mBgColorWithoutTransparency.adjustAlpha(mBgAlpha).
    private var bgColor: UInt32 {
        (UInt32((bgAlpha * 255).rounded()) << 24) | (bgColorWithoutTransparency & 0xFFFFFF)
    }

    private var notes: [Note] { store.notes }
    private var currentNote: Note? { store.note(currentNoteId) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Note", onBack: { done(false) })
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggle("Show note title", isOn: $showTitle)
                    .padding(.horizontal, -16)
                if notes.count > 1 {
                    Text("Note shown in the widget:")
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    Button { sheet = .note } label: {
                        Text(currentNote?.title ?? "General note")
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 24).stroke(palette.textColor.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(palette.textColor)
            .padding(.bottom, 16)

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                colorButton(bgColor) { sheet = .bgColor }
                Slider(value: $bgAlpha, in: 0...1)
                    .tint(palette.primaryColor)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 25).fill(palette.textColor.opacity(0.1)))
            }
            .frame(height: 50)
            .padding(.vertical, 2)
            HStack {
                colorButton(textColor) { sheet = .textColor }
                Spacer()
                Button(action: save) {
                    Text("OK")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.onPrimary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(palette.primaryColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .paletteBackground()
        .onAppear(perform: start)
        .securityCheck($check)
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .bgColor:
                    ColorPickerDialog(color: bgColorWithoutTransparency) { bgColorWithoutTransparency = $0 }
                case .textColor:
                    ColorPickerDialog(color: textColor) { textColor = $0 }
                case .note:
                    RadioDialog(title: nil, items: notes.map { ($0.noteId, $0.title) }, selected: currentNoteId) { id in
                        guard let note = store.note(id) else { return }
                        // showNoteSelector(): locked notes need their password first.
                        if !note.isLocked || note.shouldBeUnlocked {
                            currentNoteId = id
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                check = SecurityCheck(protectionType: note.protectionType, requiredHash: note.protectionHash) { _, _ in
                                    currentNoteId = id
                                }
                            }
                        }
                    }
                }
            }
            .environment(\.palette, palette)
        }
    }

    /// The live preview (text_note_view_title + text_note_view / checklist_note_view).
    @ViewBuilder
    private var preview: some View {
        if let note = currentNote {
            let stored = store.storedValue(note) ?? ""
            let value: String = {
                if note.type == .checklist {
                    let tasks = (try? JSONDecoder().decode([TaskItem].self, from: Data((stored.isEmpty ? "[]" : stored).utf8))) ?? []
                    guard tasks.isEmpty else { return stored }
                    let now = TaskItem.now()
                    return TaskItem.encode([("Milk", true), ("Butter", true), ("Salt", false), ("Water", false), ("Meat", true)]
                        .enumerated().map { TaskItem(id: $0.offset, dateCreated: now, title: $0.element.0, isDone: $0.element.1) })
                }
                return stored.isEmpty ? "Thank you for using Fossify Notes.\nFor more apps from Fossify, please visit fossify.org." : stored
            }()
            NoteWidgetBody(note: note, value: value, bgColor: bgColor, textColor: textColor, showTitle: showTitle, config: Config.shared)
        } else {
            NoteWidgetBody(note: nil, value: "", bgColor: bgColor, textColor: textColor, showTitle: showTitle, config: Config.shared)
        }
    }

    private func colorButton(_ color: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(argb: color))
                .overlay(Circle().stroke(palette.textColor.opacity(0.4), lineWidth: 1))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }

    /// NotesHelper.getNotes { ... }: preselect the first unlocked note; a single locked note asks for its password.
    private func start() {
        guard !didStart else { return }
        didStart = true
        if isReconfiguring, currentNote != nil { return }
        if let note = notes.first(where: { !$0.isLocked }) {
            currentNoteId = note.noteId
        } else if notes.count == 1, let note = notes.first {
            if note.shouldBeUnlocked {
                currentNoteId = note.noteId
            } else {
                check = SecurityCheck(protectionType: note.protectionType, requiredHash: note.protectionHash,
                                      onSuccess: { _, _ in currentNoteId = note.noteId },
                                      onFailure: { done(false) })
            }
        }
    }

    /// saveConfig() + storeWidgetBackground().
    private func save() {
        guard currentNote != nil else {
            done(false)
            return
        }
        let d = UserDefaults.standard
        d.set(Int(currentNoteId), forKey: context.key(WidgetSettings.noteIdKey))
        d.set(Int(bgColor), forKey: context.key(WidgetSettings.bgColorKey))
        d.set(Int(textColor), forKey: context.key(WidgetSettings.textColorKey))
        d.set(showTitle, forKey: context.key(WidgetSettings.showTitleKey))
        WidgetSettings.lastBgColor = bgColor
        WidgetSettings.lastTextColor = textColor
        done(true)
    }
}
