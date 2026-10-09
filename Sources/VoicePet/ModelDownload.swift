import CryptoKit
import Foundation

/// Downloads a model file to `<file>.part`, then checks it and moves it into place.
/// URLSession hands over data in chunks on its own queue, so the main thread stays idle.
/// The .part file is the resume point: after a quit, crash, or dropped connection the next
/// attempt asks for the rest with an HTTP Range request instead of starting over.
final class ModelDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private enum Failure: Error { case startOver(String) }

    private let label: String
    private let dest: URL
    private let part: URL
    private let onStatus: @Sendable (String) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var handle: FileHandle?
    private var offset: Int64 = 0       // bytes already in .part when the request went out
    private var received: Int64 = 0
    private var total: Int64 = -1
    private var lastPct = -1
    private var sha256: String?         // Hugging Face's X-Linked-Etag is the file's SHA-256
    private var failure: Error?

    init(label: String, to dest: URL, onStatus: @escaping @Sendable (String) -> Void) {
        self.label = label
        self.dest = dest
        self.part = dest.appendingPathExtension("part")
        self.onStatus = onStatus
    }

    func run(from url: URL) async throws {
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try await attempt(url)
        } catch Failure.startOver(let why) {
            // the .part we resumed from didn't fit the file on the server: throw it away and fetch it whole
            NSLog("BRAIN download starting over: %@", why)
            try? FileManager.default.removeItem(at: part)
            do { try await attempt(url) } catch Failure.startOver(let why) { throw Self.error(why) }
        }
        // a brain is in place: drop half-downloaded leftovers of other brains
        let dir = dest.deletingLastPathComponent()
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "part" {
            try? FileManager.default.removeItem(at: f)
        }
    }

    private func attempt(_ url: URL) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: part.path) { fm.createFile(atPath: part.path, contents: nil) }
        offset = ((try? fm.attributesOfItem(atPath: part.path))?[.size] as? NSNumber)?.int64Value ?? 0
        received = 0; total = -1; lastPct = -1; sha256 = nil; failure = nil
        if offset > 0 { NSLog("BRAIN resuming %@ from %lld MB", label, offset / 1_000_000) }
        var req = URLRequest(url: url)
        if offset > 0 { req.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            session.dataTask(with: req).resume()
        }
    }

    // Hugging Face answers with a redirect to its CDN; keep the Range header and note the checksum.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let tag = response.value(forHTTPHeaderField: "X-Linked-Etag")?.replacingOccurrences(of: "\"", with: "").lowercased(),
           tag.count == 64, tag.allSatisfy(\.isHexDigit) {
            sha256 = tag
        }
        var next = request
        if offset > 0 { next.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        do {
            switch http?.statusCode ?? -1 {
            case 206:
                // "bytes 1000-4999/5000": the rest of the file, starting where .part ends
                let range = http?.value(forHTTPHeaderField: "Content-Range") ?? ""
                let nums = range.split(whereSeparator: { !$0.isNumber }).compactMap { Int64($0) }
                guard nums.count == 3, nums[0] == offset else { throw Failure.startOver("unexpected range \(range)") }
                total = nums[2]
            case 200:
                // the server sent the whole file, so .part starts over
                offset = 0
                total = response.expectedContentLength
            case 416:
                throw Failure.startOver(".part is longer than the file")
            case let code:
                if offset == 0 { try? FileManager.default.removeItem(at: part) }
                throw Self.error("Model download failed with HTTP \(code)")
            }
            let h = try FileHandle(forWritingTo: part)
            try h.truncate(atOffset: UInt64(offset))
            try h.seekToEnd()
            handle = h
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { try handle?.write(contentsOf: data) } catch { failure = error; dataTask.cancel(); return }
        received += Int64(data.count)
        guard total > 0 else { return }
        let pct = Int((offset + received) * 100 / total)
        if pct != lastPct { lastPct = pct; onStatus("downloading \(label) \(pct)%") }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        do {
            if let failure { throw failure }
            if let error { throw error }
            let size = offset + received
            if total > 0, size != total { throw Self.error("Model download was incomplete (\(size) of \(total) bytes)") }
            try verify()
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: part, to: dest)
            finish(nil)
        } catch {
            finish(error)
        }
    }

    /// A GGUF header, and the SHA-256 Hugging Face published for the file when it gave one.
    private func verify() throws {
        let h = try FileHandle(forReadingFrom: part)
        defer { try? h.close() }
        guard try h.read(upToCount: 4) == Data("GGUF".utf8) else {
            try? FileManager.default.removeItem(at: part)
            throw Self.error("Model download is not a GGUF file")
        }
        guard let sha256 else { return }
        onStatus("checking \(label)")
        try h.seek(toOffset: 0)
        var hasher = SHA256()
        var more = true
        while more {
            try autoreleasepool {
                if let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) } else { more = false }
            }
        }
        let got = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard got == sha256 else {
            if offset > 0 { throw Failure.startOver("checksum mismatch after resuming") }
            try? FileManager.default.removeItem(at: part)
            throw Self.error("Model download is damaged (checksum mismatch)")
        }
    }

    private func finish(_ error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "VoicePet", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
