import Foundation
import FoundationModels

/// Turns a speaker-labelled transcript into meeting notes.
/// Claude when a key is set (best), else Apple's on-device model if Apple Intelligence is on.
enum Summarizer {
    enum Engine: String { case claude, apple }

    static var claudeKey: String {
        if let k = Keychain.get("anthropic"), !k.isEmpty { return k }
        // migrate a key saved by an older build in UserDefaults
        if let old = UserDefaults.standard.string(forKey: "claudeKey"), !old.isEmpty {
            Keychain.set(old, account: "anthropic"); UserDefaults.standard.removeObject(forKey: "claudeKey"); return old
        }
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }
    static var hasClaudeKey: Bool { !claudeKey.isEmpty }
    static var appleAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
    /// Which engine will actually run right now.
    static var active: Engine? {
        let pref = UserDefaults.standard.string(forKey: "summaryEngine") ?? "claude"
        if pref == "apple", appleAvailable { return .apple }
        if hasClaudeKey { return .claude }
        return appleAvailable ? .apple : nil
    }

    static let instructions = """
    You write meeting notes for the person who recorded the call. In the transcript that person is "Me"; the other people are labelled Speaker 1, Speaker 2, and so on unless they were renamed.

    The transcript comes from on-device speech recognition: expect misheard words, odd punctuation, and occasional wrong speaker labels. Read for meaning. When a word is clearly a mishearing, use the intended word. If a speaker introduces themselves or is addressed by name, use that name instead of their label.

    Rules:
    - Never invent facts, numbers, names, dates, or commitments that are not in the transcript.
    - Write for someone who was in the meeting and wants to remember what mattered, not a stranger.
    - Be concrete: who said what will happen, by when, and what is still undecided.
    - Plain language. No filler, no praise, no "the team discussed".
    - Write in the language the meeting was held in.

    Output Markdown in exactly this shape and nothing else:

    # <title: at most six words, specific to this meeting, no quotes>

    **TL;DR** One or two sentences that say what this meeting was about and what came out of it.

    ## Key points
    - Three to seven bullets, most important first. Each bullet is a complete thought.

    ## Decisions
    - One bullet per decision, or the single line "None made."

    ## Action items
    - [ ] Owner: what, and by when if a date was said

    ## Open questions
    - Only if there are real unanswered questions. Omit the section otherwise.

    Length: under 200 words for a meeting shorter than 20 minutes, under 350 words otherwise.
    """

    static func summarize(transcript: String) async throws -> (title: String, summary: String) {
        guard let engine = active else {
            throw NSError(domain: "VoicePet", code: 10, userInfo: [NSLocalizedDescriptionKey: "No note writer yet. Add a Claude key in the Me tab, or turn on Apple Intelligence."])
        }
        let text = engine == .claude ? try await claude(transcript) : try await apple(transcript)
        return split(text)
    }

    static func split(_ text: String) -> (String, String) {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var title = "Meeting"
        if let i = lines.firstIndex(where: { $0.hasPrefix("#") }) {
            title = lines[i].trimmingCharacters(in: CharacterSet(charactersIn: "# \"")); lines.remove(at: i)
        } else if let first = lines.first, !first.isEmpty, first.count < 80 {
            title = first.trimmingCharacters(in: CharacterSet(charactersIn: "*# \"")); lines.removeFirst()
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? "Meeting" : title, body)
    }

    // MARK: Claude (raw HTTP; there is no Swift SDK)
    static func claude(_ transcript: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(claudeKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 300
        let body: [String: Any] = [
            "model": "claude-opus-5",
            "max_tokens": 4000,
            "fallbacks": "default",
            "system": instructions,
            "messages": [["role": "user", "content": "Transcript:\n\n\(transcript)"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            let hint = http.statusCode == 401 ? " Check the key in the Me tab." : ""
            throw NSError(domain: "VoicePet", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Claude: \(msg)\(hint)"])
        }
        if json["stop_reason"] as? String == "refusal" {
            throw NSError(domain: "VoicePet", code: 11, userInfo: [NSLocalizedDescriptionKey: "Claude declined to summarize this one."])
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let out = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !out.isEmpty else { throw NSError(domain: "VoicePet", code: 12, userInfo: [NSLocalizedDescriptionKey: "Claude returned nothing."]) }
        return out
    }

    // MARK: Apple on-device (4K-token window, so long transcripts are summarized in parts)
    static func apple(_ transcript: String) async throws -> String {
        let chunks = chunk(transcript, maxWords: 1100)
        if chunks.count == 1 {
            return try await LanguageModelSession(instructions: instructions).respond(to: "Transcript:\n\n\(chunks[0])").content
        }
        var partials: [String] = []
        for (i, c) in chunks.enumerated() {
            let s = LanguageModelSession(instructions: "Summarize this part of a meeting transcript in 3-6 short bullets. Keep names, decisions, and action items. Plain text.")
            partials.append("Part \(i + 1):\n" + (try await s.respond(to: c).content))
        }
        return try await LanguageModelSession(instructions: instructions).respond(to: "Notes from each part of the meeting, in order:\n\n" + partials.joined(separator: "\n\n")).content
    }

    static func chunk(_ text: String, maxWords: Int) -> [String] {
        let lines = text.split(separator: "\n").map(String.init)
        var out: [String] = [], cur: [String] = [], n = 0
        for l in lines {
            let c = l.split(separator: " ").count
            if n + c > maxWords, !cur.isEmpty { out.append(cur.joined(separator: "\n")); cur = []; n = 0 }
            cur.append(l); n += c
        }
        if !cur.isEmpty { out.append(cur.joined(separator: "\n")) }
        return out.isEmpty ? [text] : out
    }
}
