import AVFoundation
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Records you (mic) and your call (system audio) to two CAF files, then turns them into a speaker-labelled note.
@MainActor
final class MeetingRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var elapsed: Double = 0
    @Published var currentNoteID: UUID?

    private let mic: AudioRecorder
    private let tap = SystemAudioTap()
    private var micWriter: CafWriter?
    private var sysWriter: CafWriter?
    private var timer: Timer?
    private var startedAt = Date()
    var onStateChange: ((String) -> Void)?     // pet state
    var engineProvider: () -> Transcriber = { AppleTranscriber() }
    var dictationActive: () -> Bool = { false }

    init(mic: AudioRecorder) { self.mic = mic }

    func start() {
        guard !isRecording, !isProcessing, !dictationActive() else { return }
        var note = Note()
        let dir = Store.shared.noteDir(note.id)
        do {
            micWriter = try CafWriter(url: dir.appendingPathComponent("mic.caf"))
            sysWriter = try CafWriter(url: dir.appendingPathComponent("sys.caf"))
        } catch { note.status = "failed"; note.error = "Could not create recording files"; Store.shared.upsert(note); return }
        mic.onSamples = { [weak self] s in self?.micWriter?.append(s) }
        tap.onSamples = { [weak self] s in self?.sysWriter?.append(s) }
        do { try mic.start() } catch { note.error = "Microphone unavailable" }
        do { try tap.start() } catch {
            NSLog("system audio tap failed: \(error)")
            note.error = "Couldn't hear the call (system audio permission?). Recording you only."
        }
        startedAt = Date(); elapsed = 0
        isRecording = true
        currentNoteID = note.id
        Store.shared.upsert(note)
        onStateChange?("noting")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.elapsed = Date().timeIntervalSince(self.startedAt) }
        }
    }

    func stop() {
        guard isRecording, let id = currentNoteID else { return }
        timer?.invalidate(); timer = nil
        _ = mic.stop(); mic.onSamples = nil
        tap.stop()
        isRecording = false
        let duration = Date().timeIntervalSince(startedAt)
        guard var note = Store.shared.notes.first(where: { $0.id == id }) else { return }
        note.duration = duration
        note.status = "processing"
        Store.shared.upsert(note)
        onStateChange?("thinking")
        isProcessing = true
        let engine = engineProvider()
        let vocab = Store.shared.vocabulary.words
        let micURL = micWriter!.url, sysURL = sysWriter!.url
        let group = DispatchGroup(); group.enter(); group.enter()
        micWriter?.finish { group.leave() }; sysWriter?.finish { group.leave() }
        group.notify(queue: .main) { [weak self] in
            self?.micWriter = nil; self?.sysWriter = nil
            Task {
                var n = note
                do {
                    n = try await NoteProcessor.process(note: n, micURL: micURL, sysURL: sysURL, engine: engine, vocabulary: vocab)
                    n.status = "ready"
                } catch {
                    n.status = "failed"; n.error = "\(error)"
                }
                await MainActor.run {
                    Store.shared.upsert(n)
                    self?.isProcessing = false
                    self?.onStateChange?(n.status == "ready" ? "done" : "confused")
                }
            }
        }
    }
}

enum NoteProcessor {
    static func process(note: Note, micURL: URL, sysURL: URL, engine: Transcriber, vocabulary: [String]) async throws -> Note {
        var note = note
        engine.vocabulary = vocabulary
        try await engine.prepare()
        let mic = try AudioFileLoader.load16kMono(path: micURL.path)
        let sys = try AudioFileLoader.load16kMono(path: sysURL.path)

        var words: [(TimedWord, String)] = []
        if hasSpeech(mic) {
            for w in try await engine.transcribeTimed(mic) { words.append((w, "me")) }
        }
        if hasSpeech(sys) {
            let sysWords = try await engine.transcribeTimed(sys)
            let labels = (try? await diarize(sys)) ?? []
            var idMap: [String: String] = [:]
            for w in sysWords {
                let mid = (w.start + w.end) / 2
                var spk = "s1"
                if let seg = labels.first(where: { mid >= $0.start && mid <= $0.end }) ?? labels.min(by: { abs(($0.start + $0.end) / 2 - mid) < abs(($1.start + $1.end) / 2 - mid) }) {
                    if idMap[seg.id] == nil { idMap[seg.id] = "s\(idMap.count + 1)" }
                    spk = idMap[seg.id]!
                }
                words.append((w, spk))
            }
        }
        words.sort { $0.0.start < $1.0.start }

        // group into turns
        var segments: [Segment] = []
        for (w, spk) in words {
            if var last = segments.last, last.speaker == spk, w.start - last.end < 1.5 {
                last.text += " " + w.text; last.end = max(last.end, w.end)
                segments[segments.count - 1] = last
            } else {
                segments.append(Segment(speaker: spk, start: w.start, end: w.end, text: w.text))
            }
        }
        note.segments = segments
        if segments.isEmpty { note.title = "Quiet meeting"; note.summary = ""; note.error = "I didn't hear any speech."; return note }
        note.title = fallbackTitle(segments)
        return await summarize(note)
    }

    static func fallbackTitle(_ segments: [Segment]) -> String {
        let words = segments.first?.text.split(separator: " ").prefix(6).joined(separator: " ") ?? "Meeting"
        return words.trimmingCharacters(in: .punctuationCharacters)
    }

    static func transcriptText(_ note: Note) -> String {
        note.segments.map { "\(note.name(for: $0.speaker)): \($0.text)" }.joined(separator: "\n")
    }

    /// (Re)write the notes for an existing transcript. Never throws; errors land in note.error.
    static func summarize(_ note: Note) async -> Note {
        var note = note
        note.error = nil
        do {
            let (title, summary) = try await Summarizer.summarize(transcript: transcriptText(note))
            note.title = title; note.summary = summary
        } catch {
            note.error = error.localizedDescription
        }
        return note
    }

    static func hasSpeech(_ s: [Float]) -> Bool {
        guard s.count > 16000 else { return false }
        var peak: Float = 0
        for i in stride(from: 0, to: s.count, by: 8) { peak = max(peak, abs(s[i])) }
        return peak > 0.01
    }

    struct SpeakerSpan { var id: String; var start: Double; var end: Double }
    static func diarize(_ samples: [Float], threshold: Float = 0.7) async throws -> [SpeakerSpan] {
#if canImport(FluidAudio)
        let models = try await DiarizerModels.load()
        var cfg = DiarizerConfig.default
        cfg.clusteringThreshold = threshold
        let m = DiarizerManager(config: cfg)
        m.initialize(models: models)
        let r = try m.performCompleteDiarization(samples, sampleRate: 16000)
        return r.segments.map { SpeakerSpan(id: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
#else
        throw NSError(
            domain: "VoicePet",
            code: 21,
            userInfo: [NSLocalizedDescriptionKey: "Speaker diarization requires an Apple Silicon Mac"]
        )
#endif
    }
}
