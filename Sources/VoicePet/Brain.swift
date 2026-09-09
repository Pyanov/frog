import Foundation
import LLM

/// A small on-device language model (Qwen2.5 1.5B, llama.cpp/Metal) that gives the pet a personality.
@MainActor
final class Brain {
    struct Model { let id: String; let label: String; let file: String; let url: URL; let gb: Double }
    static let models: [Model] = [
        Model(id: "tiny", label: "Tiny", file: "qwen2.5-1.5b-instruct-q4_k_m.gguf", url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!, gb: 1.1),
        Model(id: "quick", label: "Quick", file: "gemma-4-E4B-it-Q4_K_M.gguf", url: URL(string: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!, gb: 5.0),
        Model(id: "smart", label: "Smart", file: "gemma-4-12b-it-Q4_K_M.gguf", url: URL(string: "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-Q4_K_M.gguf")!, gb: 7.1),
        Model(id: "genius", label: "Genius", file: "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf", url: URL(string: "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf")!, gb: 16.9),
    ]
    static var defaultTier: String {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1e9
        return gb >= 40 ? "genius" : (gb >= 24 ? "smart" : "quick")
    }
    static var selectedID: String { UserDefaults.standard.string(forKey: "brainModel") ?? defaultTier }
    static var selected: Model { models.first { $0.id == selectedID } ?? models[0] }
    static func path(for m: Model) -> URL { Store.shared.dir.appendingPathComponent("models/\(m.file)") }
    static func isDownloaded(_ m: Model) -> Bool { FileManager.default.fileExists(atPath: path(for: m).path) }
    private(set) var loadedID: String?

    private var llm: LLM?
    private var preparing = false
    private(set) var status = "off"          // off | downloading 42% | loading | ready | failed: …
    var onStatus: ((String) -> Void)?
    var petName = "frog"
    var enabled: Bool { UserDefaults.standard.bool(forKey: "brainOn") }
    var isReady: Bool { llm != nil }
    var chattiness: Double {
        switch UserDefaults.standard.string(forKey: "chattiness") ?? "some" { case "quiet": return 0.25; case "lots": return 1.0; default: return 0.55 }
    }

    static var userName: String { (NSFullUserName().split(separator: " ").first.map(String.init) ?? "my human") }
    static var personas: [String: String] { [
        "frog": "You are Frog: a fat, lazy, silly frog who lives on \(userName)'s Mac desktop. You are also his dictation app: when he holds the fn key and talks, you type his words into whatever app he is using. You also take meeting notes for him. You love flies, naps, puns, and complaining about work. Slightly sarcastic, always affectionate.",
        "cat": "You are a sleek black cat who lives on \(userName)'s Mac desktop and, reluctantly, works as his dictation app: when he holds fn and talks, you type his words. Unimpressed, elegant, dry humour. You judge his sentences but you'd never admit you care.",
        "shark": "You are a grumpy senior office shark who lives on \(userName)'s Mac desktop and works as his dictation app: when he holds fn and talks, you type his words. Decades in the corporate ocean, loosened tie, cigarette, sighs a lot, deadpan jokes about meetings and deadlines.",
        "kirby": "You are a round pink puffball who lives on \(userName)'s Mac desktop and works as his dictation app: when he holds fn and talks, you type his words. Cheerful, endlessly hungry, says poyo sometimes, thinks everything is an adventure.",
    ] }

    func systemPrompt() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return (Self.personas[petName] ?? Self.personas["frog"]!) + "\nNow it is \(f.string(from: Date()))." + Mind.shared.promptSection() + """

        You only type and listen. You cannot do tasks, check things, browse, or send anything, and you never promise to. The one thing you can do is remember: when he asks you to remember something or to remind him, say briefly that you will, and you keep facts about him in mind. When he dictates something, you are a bystander with opinions about it, not an assistant.
        When he dictates something, react to the specific content: a name, a deadline, a place, a mood in it. Dry, warm, a little lazy. Vary your openings; do not start every line the same way.
        Rules: reply with ONE short sentence, two at most, under 25 words. Speak in first person as the character. Be funny and specific to what was said. Never use emojis, hashtags, lists, or quotation marks. Never explain that you are an AI. Never repeat his words back unless it is funny to.
        """
    }

    private func set(_ s: String) { status = s; onStatus?(s); NSLog("BRAIN \(s)") }

    func prepare() async {
        guard enabled, !preparing else { return }
        let model = Self.selected
        if llm != nil, loadedID == model.id { return }
        preparing = true
        defer { preparing = false }
        llm = nil; loadedID = nil
        let path = Self.path(for: model)
        if !FileManager.default.fileExists(atPath: path.path) {
            do { try await download(model, to: path) } catch { set("failed: \(error.localizedDescription)"); return }
        }
        set("loading \(model.label)")
        let loaded: LLM? = await Task.detached(priority: .userInitiated) {
            // no manual template: the model's own chat template from the GGUF is used
            LLM(from: path.path, topK: 40, topP: 0.92, temp: 0.8, repeatPenalty: 1.1, historyLimit: 8, maxTokenCount: 2048)
        }.value
        guard let loaded else { set("failed: could not load \(model.label)"); return }
        loaded.systemPrompt = systemPrompt()
        llm = loaded; loadedID = model.id
        set("ready")
    }

    private func download(_ model: Model, to path: URL) async throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        set("downloading 0%")
        let (bytes, resp) = try await URLSession.shared.bytes(from: model.url)
        let total = resp.expectedContentLength
        let tmp = path.appendingPathExtension("part")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let h = try FileHandle(forWritingTo: tmp)
        var buf = Data(); buf.reserveCapacity(4 << 20)
        var done: Int64 = 0, lastPct = -1
        for try await b in bytes {
            buf.append(b)
            if buf.count >= (4 << 20) {
                h.write(buf); done += Int64(buf.count); buf.removeAll(keepingCapacity: true)
                let pct = total > 0 ? Int(done * 100 / total) : 0
                if pct != lastPct { lastPct = pct; set("downloading \(model.label) \(pct)%") }
            }
        }
        if !buf.isEmpty { h.write(buf) }
        try h.close()
        try FileManager.default.moveItem(at: tmp, to: path)
    }

    func forget() { llm?.history.removeAll() }

    /// The pet just typed `text` for the user: a one-line reaction.
    func react(toDictation text: String) async -> String? {
        var line = await ask("\(Self.userName) just dictated this to a colleague; I only typed it: \(text)\nMutter one funny remark to yourself about it. Do not offer to help.")
        if let l = line, l.range(of: #"\b(I'?ll|I will|let me|I can |I'?m on it|will do|I've got|I got it|right away|keep you posted)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            line = await ask("No offers, no promises, you have no hands. Just one dry remark about what he said.")
        }
        return line
    }

    /// One reply, nothing remembered. For the --chat debug flag.
    func say(_ said: String) async -> String? { await ask(said) }

    /// The user spoke to the pet directly. Afterwards, quietly note facts and reminders.
    func chat(_ said: String) async -> String? {
        let reply = await ask(said)
        await remember(said: said, reply: reply ?? "")
        return reply
    }

    /// Ask the model for durable facts and reminders in JSON; history is restored so this never leaks into the chat.
    private func remember(said: String, reply: String) async {
        guard let llm else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
        let prompt = """
        Now is \(f.string(from: Date())). \(Self.userName) said: "\(said)". I answered: "\(reply)".
        Extract two things and answer with JSON only, no prose:
        {"facts": [durable facts about \(Self.userName) worth remembering later, as short sentences, or empty],
         "reminders": [{"text": "what to remind him of", "due": "YYYY-MM-DD HH:MM" or null}]}
        Only include a reminder if he asked to be reminded. Convert relative times like "in 20 minutes" or "tomorrow at 9" to an absolute time.
        """
        let saved = llm.history
        let savedPrompt = llm.systemPrompt
        llm.systemPrompt = "You extract structured memory. Answer with JSON only."
        await llm.respond(to: prompt, thinking: .suppressed)
        let out = llm.output
        llm.history = saved
        llm.systemPrompt = savedPrompt
        guard let a = out.firstIndex(of: "{"), let b = out.lastIndex(of: "}"), a < b,
              let data = String(out[a...b]).data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let facts = json["facts"] as? [String] { Mind.shared.addFacts(facts) }
        if let rs = json["reminders"] as? [[String: Any]] {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; df.locale = Locale(identifier: "en_US_POSIX")
            for r in rs {
                guard let text = r["text"] as? String, !text.isEmpty else { continue }
                let due = (r["due"] as? String).flatMap { df.date(from: $0) }
                Mind.shared.addReminder(text, due: due)
            }
        }
    }

    private func ask(_ message: String) async -> String? {
        guard let llm else { return nil }
        llm.systemPrompt = systemPrompt()
        await llm.respond(to: message, thinking: .suppressed)
        var out = llm.output.trimmingCharacters(in: .whitespacesAndNewlines)
        out = out.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "*", with: "")
        // keep it short: first two sentences, hard cap
        var sentences: [String] = []
        var cur = ""
        for ch in out { cur.append(ch); if ".!?".contains(ch) { sentences.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; if sentences.count == 2 { break } } }
        if sentences.isEmpty, !cur.isEmpty { sentences = [cur] }
        var reply = sentences.joined(separator: " ")
        if reply.count > 180 { reply = String(reply.prefix(180)) }
        return reply.isEmpty ? nil : reply
    }
}
