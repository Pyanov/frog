import Foundation

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var due: Date?
    var done = false
    var created = Date()
}

/// What the pet remembers about you, plus reminders it's holding. JSON in Application Support.
@MainActor
final class Mind: ObservableObject {
    static let shared = Mind()
    @Published var facts: [String] = []
    @Published var reminders: [Reminder] = []
    private var url: URL { Store.shared.dir.appendingPathComponent("mind.json") }

    private init() {
        if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: Data].self, from: d) {
            if let f = m["facts"], let v = try? JSONDecoder().decode([String].self, from: f) { facts = v }
            if let r = m["reminders"], let v = try? JSONDecoder().decode([Reminder].self, from: r) { reminders = v }
        }
    }

    private func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let f = try? enc.encode(facts), let r = try? enc.encode(reminders), let d = try? enc.encode(["facts": f, "reminders": r]) else { return }
        try? d.write(to: url, options: .atomic)
    }

    func addFacts(_ new: [String]) {
        for f in new {
            let t = f.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count > 3, !facts.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { continue }
            facts.append(t)
        }
        if facts.count > 60 { facts.removeFirst(facts.count - 60) }
        save()
    }
    func forget(_ fact: String) { facts.removeAll { $0 == fact }; save() }
    func addReminder(_ text: String, due: Date?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        reminders.append(Reminder(text: t, due: due)); save()
    }
    func update(_ r: Reminder) { if let i = reminders.firstIndex(where: { $0.id == r.id }) { reminders[i] = r; save() } }
    func remove(_ r: Reminder) { reminders.removeAll { $0.id == r.id }; save() }
    func forgetEverything() { facts = []; reminders = []; save() }

    var dueNow: [Reminder] { reminders.filter { !$0.done && ($0.due.map { $0 <= Date() } ?? false) } }

    /// Text the pet sees in its system prompt.
    func promptSection() -> String {
        var s = ""
        if !facts.isEmpty { s += "\nThings I remember about \(Brain.userName): " + facts.suffix(25).joined(separator: "; ") + "." }
        let open = reminders.filter { !$0.done }
        if !open.isEmpty {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM HH:mm"
            s += "\nReminders I'm holding: " + open.prefix(10).map { $0.text + ($0.due.map { " (\(f.string(from: $0)))" } ?? "") }.joined(separator: "; ") + "."
        }
        return s
    }
}
