import AVFoundation
import Foundation

/// The pet talks back with one of macOS's built-in novelty voices.
@MainActor
final class PetVoice: NSObject, AVSpeechSynthesizerDelegate {
    static let voices = ["Grandpa", "Rocko", "Grandma", "Bad News", "Jester", "Boing", "Bubbles", "Zarvox", "Trinoids"]
    private let synth = AVSpeechSynthesizer()
    private var lastQuip = Date.distantPast
    var onTalking: ((Bool) -> Void)?

    var enabled: Bool { UserDefaults.standard.bool(forKey: "voiceOn") }
    var readBack: Bool { UserDefaults.standard.bool(forKey: "voiceReadBack") }
    var voiceName: String { UserDefaults.standard.string(forKey: "voiceName") ?? "Grandpa" }

    override init() {
        super.init()
        synth.delegate = self
    }

    static func voice(named name: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.language.hasPrefix("en") }
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func say(_ text: String, force: Bool = false) {
        guard enabled || force, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(named: voiceName)
        u.rate = 0.48
        u.pitchMultiplier = 1.15
        u.volume = 0.9
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    /// A short remark, not every time, never twice in a row too quickly.
    func quip(_ options: [String], chance: Double = 1.0) {
        guard enabled, Date().timeIntervalSince(lastQuip) > 4, Double.random(in: 0...1) < chance else { return }
        lastQuip = Date()
        say(options.randomElement()!)
    }

    // events
    func woke() { quip(["Ribbit. I'm awake.", "Hello. Ribbit.", "Frog online.", "Ready when you are."]) }
    func dictated(_ text: String) {
        if readBack { say(text); return }
        quip(["Ribbit. Typed.", "Got it.", "Words delivered.", "Done and done.", "Sent to the keyboard.", "Nice one.", "Ribbit."], chance: 0.5)
    }
    func heardNothing() { quip(["Hmm? I didn't catch that.", "Say again?", "Ribbit? Nothing came through."]) }
    func notesStarted() { say("Taking notes. Carry on.") }
    func notesReady(title: String) { say("Notes are ready. \(title).") }
    func grabbed() { quip(["Hey!", "Ribbit!", "Careful, I'm slippery.", "Put me down.", "Whee."], chance: 0.8) }
    func test() { say("Ribbit. This is my voice. I type what you say.", force: true) }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { Task { @MainActor in self.onTalking?(true) } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.onTalking?(false) } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.onTalking?(false) } }
}
