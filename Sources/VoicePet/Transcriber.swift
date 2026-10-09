import AVFoundation
import Foundation
import Speech
#if canImport(FluidAudio)
import FluidAudio
#endif

struct TimedWord: Codable { var text: String; var start: Double; var end: Double }

protocol Transcriber: AnyObject {
    var name: String { get }
    var vocabulary: [String] { get set }
    func prepare() async throws
    func transcribe(_ samples16k: [Float]) async throws -> String
    func transcribeTimed(_ samples16k: [Float]) async throws -> [TimedWord]
}

/// Apple's on-device SpeechAnalyzer (macOS 26). No model to ship; the OS downloads the English asset once.
final class AppleTranscriber: Transcriber {
    let name = "Apple on-device"
    var vocabulary: [String] = []
    private var locale = Locale(identifier: "en-US")

    func prepare() async throws {
        try await Self.authorize()
        let supported = await SpeechTranscriber.supportedLocales
        if let l = supported.first(where: { $0.identifier(.bcp47).caseInsensitiveCompare("en-US") == .orderedSame }) { locale = l }
        let t = SpeechTranscriber(locale: locale, preset: .transcription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await req.downloadAndInstall()
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let words = try await transcribeTimed(samples)
        return Self.join(words)
    }

    func transcribeTimed(_ samples: [Float]) async throws -> [TimedWord] {
        let url = try AudioFileLoader.writeTempCAF(samples)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await transcribeTimed(fileURL: url)
    }

    func transcribeTimed(fileURL: URL) async throws -> [TimedWord] {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings = [.general: vocabulary]
            try await analyzer.setContext(ctx)
        }
        let file = try AVAudioFile(forReading: fileURL)
        let collector = Task { () throws -> [TimedWord] in
            var out: [TimedWord] = []
            for try await r in transcriber.results where r.isFinal {
                for run in r.text.runs {
                    let text = String(r.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let s = run.audioTimeRange.map { CMTimeGetSeconds($0.start) } ?? (out.last?.end ?? 0)
                    let d = run.audioTimeRange.map { CMTimeGetSeconds($0.duration) } ?? 0
                    out.append(TimedWord(text: text, start: s, end: s + d))
                }
            }
            return out
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    static func join(_ words: [TimedWord]) -> String {
        var s = ""
        for w in words {
            if !s.isEmpty, !w.text.hasPrefix(","), !w.text.hasPrefix("."), !w.text.hasPrefix("?"), !w.text.hasPrefix("!") { s += " " }
            s += w.text
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func authorize() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        }
        guard status == .authorized else { throw NSError(domain: "VoicePet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission not granted"]) }
    }
}

/// NVIDIA Parakeet TDT 0.6B v3 via FluidAudio (Core ML, Neural Engine). ~600 MB download on first use.
#if canImport(FluidAudio)
final class ParakeetTranscriber: Transcriber {
    static let isSupported = true
    let name = "Parakeet v3 on-device"
    var vocabulary: [String] = []      // Parakeet has no vocabulary biasing; replacement rules cover it
    private var manager: AsrManager?

    func prepare() async throws {
        if manager != nil { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await result(samples).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeTimed(_ samples: [Float]) async throws -> [TimedWord] {
        let r = try await result(samples)
        guard let toks = r.tokenTimings, !toks.isEmpty else {
            return [TimedWord(text: r.text, start: 0, end: Double(samples.count) / 16000)]
        }
        var words: [TimedWord] = []
        for t in toks {
            let raw = t.token
            let startsWord = raw.hasPrefix("\u{2581}") || raw.hasPrefix(" ") || words.isEmpty
            let piece = raw.replacingOccurrences(of: "\u{2581}", with: "").trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { continue }
            if startsWord { words.append(TimedWord(text: piece, start: t.startTime, end: t.endTime)) }
            else { words[words.count - 1].text += piece; words[words.count - 1].end = t.endTime }
        }
        return words
    }

    private func result(_ samples: [Float]) async throws -> ASRResult {
        try await prepare()
        guard let m = manager else { throw NSError(domain: "VoicePet", code: 2, userInfo: [NSLocalizedDescriptionKey: "Parakeet not loaded"]) }
        var state = TdtDecoderState.make(decoderLayers: await m.decoderLayerCount)
        return try await m.transcribe(samples, decoderState: &state)
    }
}
#else
final class ParakeetTranscriber: Transcriber {
    static let isSupported = false
    let name = "Parakeet v3 (requires Apple Silicon)"
    var vocabulary: [String] = []

    func prepare() async throws { throw unsupportedError }
    func transcribe(_ samples: [Float]) async throws -> String { throw unsupportedError }
    func transcribeTimed(_ samples: [Float]) async throws -> [TimedWord] { throw unsupportedError }

    private var unsupportedError: Error {
        NSError(
            domain: "VoicePet",
            code: 20,
            userInfo: [NSLocalizedDescriptionKey: "Parakeet transcription requires an Apple Silicon Mac"]
        )
    }
}
#endif
