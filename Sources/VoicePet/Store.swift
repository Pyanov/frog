import AppKit
import Foundation

struct Dictation: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var text: String
}

struct Replacement: Codable, Identifiable, Hashable {
    var id = UUID()
    var heard: String
    var meant: String
}

struct Vocabulary: Codable {
    var words: [String] = []
    var replacements: [Replacement] = []
    var heardCounts: [String: Int] = [:]      // unknown words seen in dictations, for suggestions
    var ignored: [String] = []
}

struct Segment: Codable, Identifiable, Equatable {
    var id = UUID()
    var speaker: String          // "me", "s1", "s2"...
    var start: Double
    var end: Double
    var text: String
}

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var title: String = "Untitled"
    var duration: Double = 0
    var summary: String = ""
    var segments: [Segment] = []
    var speakerNames: [String: String] = ["me": "Me"]
    var status: String = "recording"   // recording | processing | ready | failed
    var error: String? = nil

    func name(for speaker: String) -> String {
        if let n = speakerNames[speaker] { return n }
        if speaker == "me" { return "Me" }
        return "Speaker \(speaker.dropFirst())"
    }
}

/// Everything lives as JSON in ~/Library/Application Support/VoicePet.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    @Published var dictations: [Dictation] = []
    @Published var vocabulary = Vocabulary()
    @Published var notes: [Note] = []

    let dir: URL

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoicePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dictations = load("dictations.json") ?? []
        vocabulary = load("vocabulary.json") ?? Vocabulary()
        notes = load("notes.json") ?? []
        if ProcessInfo.processInfo.environment["VOICEPET_DEMO_DATA"] != nil { demoOnly = true; seedDemo() }
    }
    private var demoOnly = false

    private func seedDemo() {
        vocabulary = Vocabulary(words: ["Figma", "Anna", "Notion"], replacements: [Replacement(heard: "Ana", meant: "Anna")], heardCounts: ["Kubernetes": 3, "Typeform": 2], ignored: [])
        dictations = [Dictation(text: "Quick update on LearnVector. I talked to Safi about the HubSpot import, and we should ship the AI Andrew interview flow by Friday."),
                      Dictation(date: Date().addingTimeInterval(-1800), text: "Can you check how the waitlist is going and how the website is doing, as a separate task?")]
        var n = Note(); n.title = "Cat sitter marketplace kickoff"; n.date = Date().addingTimeInterval(-3600 * 20); n.duration = 1520; n.status = "ready"
        n.speakerNames = ["me": "Me", "s1": "Fiona"]
        n.summary = "Summary: Fiona walked through the cat-sitter marketplace idea and the go-to-market plan. Dmitry pushed on who the first customer is. Agreed to start with owners in San Francisco and recruit sitters through vet clinics.\n\nKey points:\n• Owners first, sitters recruited via clinics\n• Pricing decision deferred to next week\n• Landing page needed before outreach\n\nDecisions:\n• Start in San Francisco\n\nAction items:\n• Fiona: draft landing page copy by Friday\n• Dmitry: talk to three vet clinics"
        n.segments = [Segment(speaker: "s1", start: 0, end: 8, text: "Hi Dmitry, thanks for making time. I wanted to walk you through the cat sitter marketplace idea and get your take on the go to market plan."),
                      Segment(speaker: "me", start: 8, end: 17, text: "Sure, happy to. My first question is who the customer is. Is it the cat owner, or the sitter? Because the marketing changes a lot depending on that."),
                      Segment(speaker: "s1", start: 17, end: 26, text: "Good point. I think we start with owners in San Francisco, and we recruit sitters through vet clinics. We can decide on pricing next week."),
                      Segment(speaker: "me", start: 26, end: 32, text: "Okay. Action item for me: draft the landing page copy by Friday. And you will talk to three clinics.")]
        var n2 = Note(); n2.title = "Dylan hiring sync"; n2.date = Date().addingTimeInterval(-3600 * 30); n2.duration = 2210; n2.status = "ready"; n2.summary = "Summary: Reviewed the five job descriptions."
        notes = [n, n2]
    }

    func noteDir(_ id: UUID) -> URL {
        let u = dir.appendingPathComponent("notes/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private func save<T: Encodable>(_ v: T, _ name: String) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(v) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
    }
    func persist() {
        if demoOnly { return }
        save(dictations, "dictations.json")
        save(vocabulary, "vocabulary.json")
        save(notes, "notes.json")
    }

    // MARK: dictations + learning

    func recordDictation(_ text: String) {
        dictations.insert(Dictation(text: text), at: 0)
        if dictations.count > 200 { dictations.removeLast(dictations.count - 200) }
        learn(from: text)
        persist()
    }

    /// Words the spell checker doesn't know are probably names; count them so we can suggest adding them.
    func learn(from text: String) {
        let known = Set(vocabulary.words.map { $0.lowercased() })
        let ignored = Set(vocabulary.ignored.map { $0.lowercased() })
        let checker = NSSpellChecker.shared
        let ns = text as NSString
        var at = 0
        while at < ns.length {
            let r = checker.checkSpelling(of: text, startingAt: at, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if r.location == NSNotFound || r.length == 0 { break }
            let w = ns.substring(with: r).trimmingCharacters(in: .punctuationCharacters)
            at = r.location + r.length
            guard w.count >= 3, !known.contains(w.lowercased()), !ignored.contains(w.lowercased()) else { continue }
            vocabulary.heardCounts[w, default: 0] += 1
        }
    }

    var suggestions: [String] {
        vocabulary.heardCounts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.map { $0.key }
    }

    func addWord(_ w: String) {
        let w = w.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !vocabulary.words.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) else { return }
        vocabulary.words.append(w)
        vocabulary.heardCounts[w] = nil
        persist()
    }
    func removeWord(_ w: String) { vocabulary.words.removeAll { $0 == w }; persist() }
    func ignoreSuggestion(_ w: String) { vocabulary.ignored.append(w); vocabulary.heardCounts[w] = nil; persist() }
    func addReplacement(heard: String, meant: String) {
        let h = heard.trimmingCharacters(in: .whitespaces), m = meant.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, !m.isEmpty else { return }
        vocabulary.replacements.removeAll { $0.heard.caseInsensitiveCompare(h) == .orderedSame }
        vocabulary.replacements.append(Replacement(heard: h, meant: m))
        addWord(m)
    }
    func removeReplacement(_ r: Replacement) { vocabulary.replacements.removeAll { $0.id == r.id }; persist() }

    /// Apply "when I say X, write Y" rules (whole words, case-insensitive).
    func applyReplacements(_ text: String) -> String {
        var out = text
        for r in vocabulary.replacements {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: r.heard) + "\\b"
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: r.meant), options: .regularExpression)
        }
        return out
    }

    /// The user fixed a dictation by hand: turn single-word substitutions into rules.
    func learnFix(original: String, edited: String, dictationID: UUID?) {
        if let i = dictations.firstIndex(where: { $0.id == dictationID }) { dictations[i].text = edited }
        let a = original.split(separator: " ").map(String.init), b = edited.split(separator: " ").map(String.init)
        if a.count == b.count {
            for (x, y) in zip(a, b) where x != y {
                let hx = x.trimmingCharacters(in: .punctuationCharacters), hy = y.trimmingCharacters(in: .punctuationCharacters)
                if !hx.isEmpty, !hy.isEmpty, hx.lowercased() != hy.lowercased() { addReplacement(heard: hx, meant: hy) }
            }
        }
        persist()
    }

    // MARK: notes
    func upsert(_ note: Note) {
        if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note } else { notes.insert(note, at: 0) }
        persist()
    }
    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("notes/\(note.id.uuidString)"))
        persist()
    }
}
