import AppKit

/// Hold-to-talk on the Fn (Globe) key. Needs Accessibility trust for the global monitor.
/// macOS must have "Press fn key to: Do Nothing" set, or the Globe key also opens emoji/dictation.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onTalkPress: (() -> Void)?
    var onTalkRelease: (() -> Void)?
    private var monitors: [Any] = []
    private var down = false
    private var talkDown = false
    private let fnKeyCode: UInt16 = 63
    private let rightOptionKeyCode: UInt16 = 61

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] e in self?.handle(e) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in handler(e); return e }) { monitors.append(m) }
    }

    private func handle(_ e: NSEvent) {
        if e.keyCode == fnKeyCode {
            let isDown = e.modifierFlags.contains(.function)
            if isDown && !down { down = true; onPress?() }
            else if !isDown && down { down = false; onRelease?() }
        } else if e.keyCode == rightOptionKeyCode {
            let isDown = e.modifierFlags.contains(.option)
            if isDown && !talkDown { talkDown = true; onTalkPress?() }
            else if !isDown && talkDown { talkDown = false; onTalkRelease?() }
        }
    }
}

/// Feeds the global cursor position to the pet so its eyes can follow you.
final class CursorTracker {
    static let shared = CursorTracker()
    var onMove: ((Double, Double) -> Void)?
    private var monitor: Any?
    private var last = Date.distantPast

    func start(panel: NSWindow) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            let now = Date()
            guard now.timeIntervalSince(self.last) > 1.0 / 20.0 else { return }
            self.last = now
            let p = NSEvent.mouseLocation
            let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            // normalised offset from the pet, clamped to [-1, 1]
            let nx = max(-1, min(1, (p.x - c.x) / 400))
            let ny = max(-1, min(1, (p.y - c.y) / 400))
            self.onMove?((nx * 100).rounded() / 100, (ny * 100).rounded() / 100)
        }
    }
}
