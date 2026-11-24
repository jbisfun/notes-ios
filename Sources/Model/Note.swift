import FossifyCommons
import Foundation

/// NoteType; serialized by name like kotlinx.serialization does ("TYPE_TEXT").
enum NoteType: Int, Codable {
    case text = 0, checklist = 1

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            self = NoteType(rawValue: i) ?? .text
        } else {
            self = (try? c.decode(String.self)) == "TYPE_CHECKLIST" ? .checklist : .text
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self == .checklist ? "TYPE_CHECKLIST" : "TYPE_TEXT")
    }
}

/// models/Note.kt. `path` links the note with a file: a base64 security-scoped bookmark here
/// (a file path / content:// URI on Android); `value` is then unused.
struct Note: Codable, Hashable {
    var id: Int64?
    var title: String
    var value: String
    var type: NoteType
    var path: String
    var protectionType: Int
    var protectionHash: String

    init(id: Int64? = nil, title: String, value: String = "", type: NoteType, path: String = "",
         protectionType: Int = Protection.none, protectionHash: String = "") {
        self.id = id
        self.title = title
        self.value = value
        self.type = type
        self.path = path
        self.protectionType = protectionType
        self.protectionHash = protectionHash
    }

    var noteId: Int64 { id ?? 0 }
    var isLocked: Bool { protectionType != Protection.none }

    /// shouldBeUnlocked(): biometric protection on a device without biometrics.
    var shouldBeUnlocked: Bool { protectionType == Protection.biometric && !Protection.biometricAvailable }
}

/// models/Task.kt (Gson JSON: id, dateCreated, title, isDone).
struct TaskItem: Codable, Hashable, Identifiable {
    var id: Int
    var dateCreated: Int64
    var title: String
    var isDone: Bool

    init(id: Int, dateCreated: Int64 = 0, title: String, isDone: Bool) {
        self.id = id
        self.dateCreated = dateCreated
        self.title = title
        self.isDone = isDone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        dateCreated = try c.decodeIfPresent(Int64.self, forKey: .dateCreated) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
    }

    /// Task.compareTo() with Task.sorting (CollatorBasedComparator ~ localizedStandardCompare).
    static func sorted(_ tasks: [TaskItem], sorting: Int) -> [TaskItem] {
        let descending = sorting & Sort.descending != 0
        return tasks.enumerated().sorted { a, b in
            var r: ComparisonResult
            if sorting & Sort.byTitle != 0 {
                r = a.element.title.localizedStandardCompare(b.element.title)
            } else {
                r = a.element.dateCreated == b.element.dateCreated ? .orderedSame
                    : (a.element.dateCreated < b.element.dateCreated ? .orderedAscending : .orderedDescending)
            }
            if r == .orderedSame { return a.offset < b.offset }
            return descending ? r == .orderedDescending : r == .orderedAscending
        }.map(\.element)
    }

    static func encode(_ tasks: [TaskItem]) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return (try? e.encode(tasks)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

extension String {
    /// parseChecklistItems().
    func parseChecklistItems() -> [TaskItem]? {
        guard hasPrefix("[{") && hasSuffix("}]") else { return nil }
        return try? JSONDecoder().decode([TaskItem].self, from: Data(utf8))
    }

    /// checklistToPlainText().
    func checklistToPlainText(moveDoneToBottom: Bool = true) -> String? {
        guard let tasks = parseChecklistItems() else { return nil }
        let sorted = moveDoneToBottom ? tasks.enumerated().sorted { ($0.element.isDone ? 1 : 0, $0.offset) < ($1.element.isDone ? 1 : 0, $1.offset) }.map(\.element) : tasks
        return sorted.map { "\($0.isDone ? "[x]" : "[ ]") \($0.title)" }.joined(separator: "\n")
    }

    /// The word counter of TextFragment.setWordCounter().
    var wordCount: Int {
        replacingOccurrences(of: "\n", with: " ").split(separator: " ", omittingEmptySubsequences: true).count
    }

    /// String.isMediaFile().
    var isMediaFile: Bool {
        let ext = (self as NSString).pathExtension.lowercased()
        let media: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "heif", "svg", "tiff", "dng", "raw",
                                  "mp4", "mkv", "webm", "avi", "3gp", "mov", "m4v", "3gpp",
                                  "mp3", "wav", "wma", "ogg", "m4a", "opus", "flac", "aac", "m4b"]
        return media.contains(ext)
    }
}
