import Foundation

/// An open to-do with a date: `- [ ] call Sam 📅 2026-10-07 15:00`.
/// Same format as the Obsidian Tasks plugin, so the files work there too.
struct Reminder: Hashable, Sendable {
    var noteID: UUID
    var noteTitle: String
    var text: String
    var date: Date
    var hasTime: Bool

    /// Stable across rescans, so rescheduling never duplicates a notification.
    var identifier: String {
        // FNV-1a: `hashValue` is reseeded every launch, this isn't.
        let hash = text.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        return "jot.\(noteID.uuidString).\(Int(date.timeIntervalSince1970)).\(String(hash, radix: 36))"
    }
}

enum ReminderScanner {
    private static let task = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+\[( )\]\s+(.*)$"#)
    private static let due = try! NSRegularExpression(pattern: #"📅\x{FE0F}?\s?(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{1,2}):(\d{2}))?"#)

    /// Open (unticked) to-dos that carry a date.
    static func scan(_ markdown: String, noteID: UUID, noteTitle: String, calendar: Calendar = .current) -> [Reminder] {
        var found: [Reminder] = []
        var inFence = false
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = task.firstMatch(in: line, range: range),
                  let bodyRange = Range(match.range(at: 2), in: line) else { continue }
            let body = String(line[bodyRange])
            guard let date = due.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) else { continue }
            func int(_ group: Int) -> Int? {
                guard let range = Range(date.range(at: group), in: body) else { return nil }
                return Int(body[range])
            }
            guard let year = int(1), let month = int(2), let day = int(3) else { continue }
            let hour = int(4)
            var parts = DateComponents(year: year, month: month, day: day)
            parts.hour = hour ?? 0
            parts.minute = int(5) ?? 0
            guard let when = calendar.date(from: parts) else { continue }
            let text = plain(body.replacingOccurrences(of: #"📅\x{FE0F}?\s?\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{2})?"#, with: "", options: .regularExpression))
            found.append(Reminder(noteID: noteID, noteTitle: noteTitle, text: text, date: when, hasTime: hour != nil))
        }
        return found
    }

    /// Markdown → readable text for a notification.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_~=`]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
