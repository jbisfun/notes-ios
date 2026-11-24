# notes-ios

[Fossify Notes](https://github.com/FossifyOrg/Notes) re-created for iOS in SwiftUI.

    idl build -c release     # -> build/release/FossifyNotes.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyNotes

Ported: text notes and checklists in a swipeable pager with the note title strip; undo/redo, search (system find bar), word count, clickable links, monospaced font, alignment, font size and line wrap; checklists with check/uncheck, checked items collapsed at the bottom, sorting (per checklist too), drag reordering, move to top/bottom, rename, delete and multi-line add; open note grid with previews, new/rename/delete note, lock notes with pattern, PIN or Face ID/Touch ID; open files and folders (copied or kept in sync with the file), open text files from other apps, export as file, share, print; export/import all notes as JSON (Fossify's format), automatic backups (Files › On My iPhone › Notes › Backups or a chosen folder); autosave or manual save with the unsaved-changes prompt, app and deletion password protection, colors and every applicable setting.

Differences forced by iOS: no home-screen widget (it would need a WidgetKit extension plus an App Group) and so no widget colors; no launcher or pinned note shortcuts; text shared from other apps can't be added to a note (needs a share extension); automatic backups run when the app is opened after 6 AM instead of from an alarm; "Incognito mode" turns off autocorrection and predictions (iOS keyboards have no incognito flag); no in-app language switch.

GPL-3.0, like the original.
