import AppKit
import AVFoundation
import Speech

// Debug entry points (no UI):
//   VoicePet --transcribe file.wav [apple|parakeet]
//   VoicePet --diarize file.wav
//   VoicePet --summarize transcript.txt
//   VoicePet --tap-test 5            capture 5s of system audio, transcribe it
//   VoicePet --chat "hey" ["..."]     load the brain once, print its reply to each message (no memory writes)
//   VoicePet --react "text" ["..."]   the frog's remark after typing each dictation (no memory writes)
//   VoicePet --speak "text" out.caf    render a line with the pet's own voice settings to an audio file
/// Collects AVSpeechSynthesizer.write buffers into one audio file.
final class SpeechFileWriter: @unchecked Sendable {
    private let url: URL
    private var file: AVAudioFile?
    private var frames: Int64 = 0
    private var rate: Double = 22050
    private let q = DispatchQueue(label: "speechwriter")
    init(url: URL) { self.url = url }
    func write(_ pcm: AVAudioPCMBuffer) {
        q.sync {
            if file == nil { file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved); rate = pcm.format.sampleRate }
            try? file?.write(from: pcm); frames += Int64(pcm.frameLength)
        }
    }
    private var finished = false
    /// True the first time only; the synthesizer sends more than one empty buffer at the end.
    func finish() -> Bool { q.sync { if finished { return false }; finished = true; file = nil; return true } }
    var seconds: Double { q.sync { Double(frames) / rate } }
}

final class SampleSink: @unchecked Sendable {
    private var buf: [Float] = []
    private let q = DispatchQueue(label: "sink")
    func append(_ s: [Float]) { q.sync { buf.append(contentsOf: s) } }
    func drain() -> [Float] { q.sync { buf } }
}

func runDebug(_ args: [String]) -> Bool {
    guard args.count >= 2, ["--transcribe", "--diarize", "--summarize", "--tap-test", "--check", "--brain", "--chat", "--react", "--speak"].contains(args[1]) else { return false }
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            switch args[1] {
            case "--transcribe":
                let engine: Transcriber = (args.count >= 4 && args[3] == "parakeet") ? ParakeetTranscriber() : AppleTranscriber()
                let t0 = Date(); try await engine.prepare(); let t1 = Date()
                let samples = try AudioFileLoader.load16kMono(path: args[2])
                let words = try await engine.transcribeTimed(samples); let t2 = Date()
                print("[\(engine.name)] \(AppleTranscriber.join(words))")
                print("words: \(words.count), first: \(words.prefix(3).map { "\($0.text)@\(String(format: "%.2f", $0.start))" })")
                print(String(format: "prepare %.2fs | transcribe %.2fs | audio %.1fs", t1.timeIntervalSince(t0), t2.timeIntervalSince(t1), Double(samples.count) / 16000))
            case "--diarize":
                let samples = try AudioFileLoader.load16kMono(path: args[2])
                let t0 = Date()
                let th = Float(args.count >= 4 ? args[3] : "0.7") ?? 0.7
                let spans = try await NoteProcessor.diarize(samples, threshold: th)
                print(String(format: "diarized %.1fs of audio in %.2fs", Double(samples.count) / 16000, Date().timeIntervalSince(t0)))
                for s in spans { print(String(format: "  %@  %.2f – %.2f", s.id, s.start, s.end)) }
            case "--summarize":
                let text = try String(contentsOfFile: args[2], encoding: .utf8)
                print("apple available: \(Summarizer.appleAvailable), active engine: \(String(describing: Summarizer.active))")
                let (title, body) = try await Summarizer.summarize(transcript: text)
                print("TITLE: \(title)\n\(body)")
            case "--brain":
                UserDefaults.standard.set(true, forKey: "brainOn")
                let brain = await Brain()
                await brain.prepare()
                print("status: \(await brain.status)")
                var t0 = Date()
                print("react: \(await brain.react(toDictation: args.count >= 3 ? args[2] : "We should ship the new onboarding flow by Friday.") ?? "nil")")
                print(String(format: "  %.2fs", Date().timeIntervalSince(t0))); t0 = Date()
                print("chat:  \(await brain.chat("Hey frog, how is your day going? Also remind me in 20 minutes to call Anna.") ?? "nil")")
                print(String(format: "  %.2fs incl. memory extraction", Date().timeIntervalSince(t0)))
                print("reminders: \(await Mind.shared.reminders.map { "\($0.text) @ \($0.due.map { "\($0)" } ?? "no time")" })")
                print("facts: \(await Mind.shared.facts)")
            case "--chat":
                UserDefaults.standard.set(true, forKey: "brainOn")
                let brain = await Brain()
                await brain.prepare()
                print("status: \(await brain.status)")
                for m in args.dropFirst(2) { print("> \(m)"); print(await brain.say(m) ?? "nil") }
            case "--react":
                UserDefaults.standard.set(true, forKey: "brainOn")
                let brain = await Brain()
                await brain.prepare()
                print("status: \(await brain.status)")
                for m in args.dropFirst(2) { print("> \(m)"); print(await brain.react(toDictation: m) ?? "nil") }
            case "--speak":
                guard args.count >= 4 else { print("usage: --speak \"text\" out.caf"); break }
                let out = URL(fileURLWithPath: args[3])
                try? FileManager.default.removeItem(at: out)
                let u = AVSpeechUtterance(string: args[2])
                let name = UserDefaults.standard.string(forKey: "voiceName") ?? "Grandpa"
                u.voice = await MainActor.run { PetVoice.voice(named: name) }
                u.rate = 0.48
                u.pitchMultiplier = 1.15
                u.volume = 0.9
                let synth = AVSpeechSynthesizer()
                let writer = SpeechFileWriter(url: out)
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    synth.write(u) { buffer in
                        if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 { writer.write(pcm) } else if writer.finish() { c.resume() }
                    }
                }
                print("wrote \(out.path) (\(String(format: "%.2f", writer.seconds))s, voice \(u.voice?.name ?? "?"))")
            case "--check":
                print("accessibility trusted: \(Permissions.accessibilityTrusted)")
                print("mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = authorized)")
                print("speech: \(SFSpeechRecognizer.authorizationStatus().rawValue) (3 = authorized)")
                print("fn key does something else: \(Permissions.fnKeyDoesSomethingElse)")
            case "--tap-test":
                let secs = Double(args.count >= 3 ? args[2] : "5") ?? 5
                let tap = SystemAudioTap()
                let sink = SampleSink()
                tap.onSamples = { s in sink.append(s) }
                try tap.start()
                print("tap started, capturing \(secs)s of system audio…")
                try await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                tap.stop()
                let samples = sink.drain()
                var peak: Float = 0; for s in samples { peak = max(peak, abs(s)) }
                print(String(format: "captured %.1fs, peak %.3f", Double(samples.count) / 16000, peak))
                var rms: [String] = []
                for sec in stride(from: 0, to: samples.count, by: 16000) {
                    let slice = samples[sec..<min(sec + 16000, samples.count)]
                    rms.append(String(format: "%.2f", (slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot()))
                }
                print("rms/sec: \(rms.joined(separator: " "))")
                let dump = try AudioFileLoader.writeTempCAF(samples); print("saved \(dump.path)")
                let engine = AppleTranscriber(); try await engine.prepare()
                print("heard: \(try await engine.transcribe(samples))")
            default:
                print("unknown flag \(args[1])")
            }
        } catch { print("error: \(error)") }
        sem.signal()
    }
    while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    return true
}

if runDebug(CommandLine.arguments) { exit(0) }

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
