import FossifyCommons
import SwiftUI
import UIKit

/// note_locked_layout: shown instead of a locked note's content.
struct LockedNoteView: View {
    @Environment(\.palette) private var palette
    @Environment(Config.self) private var config
    let onShow: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock").font(.system(size: 44)).foregroundStyle(palette.textColor)
            Text("The notes' content is locked.")
                .font(.system(size: config.percentageFontSize))
                .multilineTextAlignment(.center)
            Button(action: onShow) {
                Text("Show content").underline().font(.system(size: config.percentageFontSize)).foregroundStyle(palette.primaryColor)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// TextFragment.
struct TextNotePage: View {
    @Environment(NotesStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let note: Note
    let session: NoteSession
    let onUnlock: () -> Void

    var body: some View {
        Group {
            if note.isLocked && !session.unlocked {
                LockedNoteView(onShow: onUnlock)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    NoteTextView(
                        session: session,
                        font: config.monospacedFont
                            ? .monospacedSystemFont(ofSize: config.percentageFontSize, weight: .regular)
                            : .systemFont(ofSize: config.percentageFontSize),
                        alignment: [.left, .center, .right][config.gravity.rawValue],
                        textColor: UIColor(palette.textColor),
                        tint: UIColor(palette.primaryColor),
                        lineWrap: config.enableLineWrap,
                        clickableLinks: config.clickableLinks,
                        incognito: config.useIncognitoMode,
                        placeCursorToEnd: config.placeCursorToEnd
                    )
                    .id(config.enableLineWrap)
                    if config.showWordCount {
                        Text("\(session.text.wordCount)")
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .onAppear { store.loadText(session) }
    }
}

/// TasksFragment + TasksAdapter.
struct ChecklistPage: View {
    @Environment(NotesStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let note: Note
    let session: NoteSession
    let onUnlock: () -> Void
    let onAddItems: () -> Void

    var body: some View {
        Group {
            if note.isLocked && !session.unlocked {
                LockedNoteView(onShow: onUnlock)
            } else if session.loaded && session.tasks.isEmpty {
                VStack(spacing: 12) {
                    Text("The checklist is empty").font(.system(size: config.percentageFontSize))
                    Button(action: onAddItems) {
                        Text("Add new checklist items").underline().font(.system(size: config.percentageFontSize))
                            .foregroundStyle(palette.primaryColor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !note.isLocked || session.unlocked {
                Button(action: { session.selected.removeAll(); onAddItems() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(palette.onPrimary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(palette.primaryColor))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .padding(16)
            }
        }
        .onAppear { store.loadTasks(session) }
        .onChange(of: config.sortingRevision) { store.applySorting(session) }
        .onChange(of: config.sorting) { store.applySorting(session) }
    }

    private var list: some View {
        let moveDone = config.moveDoneChecklistItems
        let unchecked = moveDone ? session.tasks.filter { !$0.isDone } : session.tasks
        let checked = moveDone ? session.tasks.filter(\.isDone) : []
        let expanded = unchecked.isEmpty ? true : session.expanded
        return List {
            ForEach(unchecked) { task in row(task) }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    store.moveTask(session, from: f, to: to > f ? to - 1 : to)
                }
            if !checked.isEmpty {
                Button {
                    session.expanded = !expanded
                } label: {
                    VStack(spacing: 0) {
                        Divider().overlay(palette.divider)
                        HStack(spacing: 12) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            Text("\(checked.count) checked item\(checked.count == 1 ? "" : "s")")
                                .font(.system(size: config.percentageFontSize))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
                if expanded {
                    ForEach(checked) { task in row(task).moveDisabled(true) }
                }
            }
            Color.clear.frame(height: 72).listRowBackground(Color.clear).listRowSeparator(.hidden).moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(session.selected.isEmpty ? .inactive : .active))
    }

    private func row(_ task: TaskItem) -> some View {
        let selected = session.selected.contains(task.id)
        let alignment: Alignment = [.leading, .center, .trailing][config.gravity.rawValue]
        return HStack(spacing: 12) {
            Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                .font(.system(size: 22))
                .foregroundStyle(task.isDone ? palette.primaryColor : palette.secondaryText)
            Text(task.title)
                .font(.system(size: config.percentageFontSize))
                .strikethrough(task.isDone)
                .opacity(task.isDone ? 0.4 : 1)
                .multilineTextAlignment([.leading, .center, .trailing][config.gravity.rawValue])
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if session.selected.isEmpty {
                store.toggleTask(session, task)
            } else if selected {
                session.selected.remove(task.id)
            } else {
                session.selected.insert(task.id)
            }
        }
        .onLongPressGesture {
            toggleSelection(task.id, in: &session.selected)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(selected ? palette.primaryColor.opacity(0.25) : Color.clear)
    }
}
