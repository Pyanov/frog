import AVFoundation
import CoreAudio
import Foundation

/// Captures everything the Mac is playing (the other side of a call) with a Core Audio process tap.
/// Delivers 16 kHz mono Float32 chunks. Needs the "System Audio Recording" permission (NSAudioCaptureUsageDescription).
final class SystemAudioTap {
    enum TapError: Error { case osStatus(OSStatus, String) }

    var onSamples: (([Float]) -> Void)?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "voicepet.systemtap")
    private var tapFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    func start() throws {
        let desc = CATapDescription(monoGlobalTapButExcludeProcesses: Self.ownProcessObject().map { [$0] } ?? [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(desc, &tap)
        guard err == noErr else { throw TapError.osStatus(err, "create tap") }
        tapID = tap

        let outputUID = try Self.defaultOutputDeviceUID()
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VoicePet Tap",
            kAudioAggregateDeviceUIDKey: "voicepet-tap-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg)
        guard err == noErr else { cleanup(); throw TapError.osStatus(err, "create aggregate device") }
        aggregateID = agg

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        err = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd)
        guard err == noErr, let fmt = AVAudioFormat(streamDescription: &asbd) else { cleanup(); throw TapError.osStatus(err, "tap format") }
        tapFormat = fmt
        converter = AVAudioConverter(from: fmt, to: target)

        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inInputData, _, _, _ in
            guard let self, let fmt = self.tapFormat else { return }
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            self.handle(buf)
        }
        guard err == noErr else { cleanup(); throw TapError.osStatus(err, "io proc") }
        err = AudioDeviceStart(aggregateID, procID)
        guard err == noErr else { cleanup(); throw TapError.osStatus(err, "start") }
    }

    func stop() { cleanup() }

    private func cleanup() {
        if aggregateID != kAudioObjectUnknown {
            if let p = procID { AudioDeviceStop(aggregateID, p); AudioDeviceDestroyIOProcID(aggregateID, p); procID = nil }
            AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    private func handle(_ buf: AVAudioPCMBuffer) {
        guard let converter, buf.frameLength > 0 else { return }
        let ratio = target.sampleRate / buf.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * ratio) + 32) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, let ch = out.floatChannelData, out.frameLength > 0 else { return }
        onSamples?(Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))))
    }

    /// Core Audio object for this process, used to exclude our own sound effects from the tap.
    static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let err = withUnsafeMutablePointer(to: &pid) { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), $0, &size, &obj) }
        return err == noErr && obj != kAudioObjectUnknown ? obj : nil
    }

    static func defaultOutputDeviceUID() throws -> String {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        guard err == noErr else { throw TapError.osStatus(err, "default output") }
        var uid: CFString = "" as CFString
        var usize = UInt32(MemoryLayout<CFString>.size)
        var uaddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        err = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(dev, &uaddr, 0, nil, &usize, $0) }
        guard err == noErr else { throw TapError.osStatus(err, "output uid") }
        return uid as String
    }
}

/// Streams 16 kHz mono samples to a CAF file so long recordings never sit in RAM.
final class CafWriter {
    private let file: AVAudioFile
    private let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let q = DispatchQueue(label: "voicepet.cafwriter")
    private(set) var frames: Int = 0
    let url: URL

    init(url: URL) throws {
        self.url = url
        file = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }
    func append(_ samples: [Float]) {
        q.async {
            guard !samples.isEmpty, let buf = AVAudioPCMBuffer(pcmFormat: self.fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            try? self.file.write(from: buf)
            self.frames += samples.count
        }
    }
    func finish(_ done: @escaping () -> Void) { q.async { done() } }
}
