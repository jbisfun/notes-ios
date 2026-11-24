import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// SettingsActivity.
struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(NotesStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var pickFontSize = false
    @State private var pickGravity = false
    @State private var exportNotes = false
    @State private var unlockNotes: [Note]?
    @State private var manageBackups: ManageMode?
    @State private var exportDocument: TextFile?
    @State private var exportName = ""
    @State private var importing = false

    enum ManageMode: Identifiable {
        case enable, manage
        var id: Self { self }
    }

    private static let fontSizes = [50, 60, 75, 90, 100, 125, 150, 175, 200, 250, 300]

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Font size", value: "\(config.fontSizePercentage)%") { pickFontSize = true }

                    Text("Text").sectionHeader(palette)
                    SettingsToggle("Show word count", isOn: $config.showWordCount)
                    SettingsToggle("Make links and emails clickable", isOn: $config.clickableLinks)
                    SettingsToggle("Use monospaced font", isOn: $config.monospacedFont)
                    SettingsToggle("Use Incognito mode of keyboards", isOn: $config.useIncognitoMode)
                    SettingsToggle("Enable line wrap", isOn: $config.enableLineWrap)
                    SettingsToggle("Move checked items to the bottom", isOn: $config.moveDoneChecklistItems)
                    SettingsItem("Alignment", value: config.gravity.title) { pickGravity = true }

                    Text("Startup").sectionHeader(palette)
                    SettingsToggle("Place cursor to the end of note", isOn: $config.placeCursorToEnd)
                    SettingsToggle("Show keyboard on startup", isOn: $config.showKeyboard)
                    if store.notes.count > 1 {
                        SettingsToggle("Show a note picker on startup", isOn: $config.showNotePicker)
                    }

                    Text("Saving").sectionHeader(palette)
                    SettingsToggle("Autosave notes", isOn: $config.autosaveNotes)
                    SettingsToggle("Display save success messages", isOn: $config.displaySuccess)

                    Text("Security").sectionHeader(palette)
                    PasswordProtectionToggle("Password protect the whole application", kind: .app)
                    PasswordProtectionToggle("Password protect note deletion", kind: .delete)

                    Text("Backups").sectionHeader(palette)
                    SettingsToggle("Enable automatic backups", isOn: Binding(get: { config.autoBackup }, set: { on in
                        if on { manageBackups = .enable } else { config.autoBackup = false }
                    }))
                    if config.autoBackup {
                        SettingsItem("Manage automatic backups") { manageBackups = .manage }
                    }

                    Text("Migrating").sectionHeader(palette)
                    SettingsItem("Export notes") { exportNotes = true }
                    SettingsItem("Import notes") { importing = true }
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $pickFontSize) {
            RadioDialog(title: nil, items: Self.fontSizes.map { ($0, "\($0)%") }, selected: config.fontSizePercentage) {
                config.fontSizePercentage = $0
            }
        }
        .sheet(isPresented: $pickGravity) {
            RadioDialog(title: nil, items: Gravity.allCases.map { ($0, $0.title) }, selected: config.gravity) { config.gravity = $0 }
        }
        .sheet(isPresented: $exportNotes) {
            ExportNotesDialog { filename in
                exportName = "\(filename).json"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { requestUnlock() }
            }
        }
        .sheet(item: Binding(get: { unlockNotes.map(LockedNotes.init) }, set: { if $0 == nil { unlockNotes = nil } })) { locked in
            UnlockNotesDialog(notes: locked.notes) { unlocked in
                let toExport = unlocked + store.notes.filter { !$0.isLocked }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { export(toExport) }
            }
        }
        .sheet(item: $manageBackups) { mode in
            ManageAutoBackupsDialog {
                if mode == .enable { config.autoBackup = true }
            }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            exportDocument = nil
            switch result {
            case .success: store.toast = "Exporting successful"
            case .failure(let e): store.toast = e.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            if case .success(let url) = result { importNotes(url) }
        }
    }

    /// requestUnlockNotes().
    private func requestUnlock() {
        let locked = store.notes.filter(\.isLocked)
        if locked.isEmpty { export(store.notes) } else { unlockNotes = locked }
    }

    private func export(_ notes: [Note]) {
        if notes.isEmpty {
            store.toast = "No entries for exporting have been found"
            return
        }
        exportDocument = TextFile(data: NotesStore.exportData(notes))
    }

    private func importNotes(_ url: URL) {
        store.toast = "Importing…"
        do {
            let (text, _) = try FileLink.readPicked(url)
            guard let notes = try? JSONDecoder().decode([Note].self, from: Data(text.utf8)) else {
                store.toast = "Invalid file format"
                return
            }
            if notes.isEmpty {
                store.toast = "No entries for importing have been found"
                return
            }
            switch store.importNotes(notes) {
            case .ok: store.toast = "Importing successful"
            case .partial: store.toast = "Importing some entries failed"
            case .nothingNew: store.toast = "No new items have been found"
            case .fail: store.toast = "Importing failed"
            }
        } catch {
            store.toast = error.localizedDescription
        }
    }
}

private struct LockedNotes: Identifiable {
    let notes: [Note]
    var id: Int { notes.count }
}

extension AppInfo {
    public static let notes = AppInfo(name: "Notes", icon: "note.text", upstream: "Notes", port: "notes-ios", policy: "notes")
}
