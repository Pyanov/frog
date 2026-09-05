import AppKit
import Carbon.HIToolbox

/// Puts text into the frontmost app.
/// Short text is typed as synthetic key events (no clipboard involved, works in terminals).
/// Long text goes through the clipboard + Cmd+V, restoring the old clipboard well after the paste.
final class Paster {
    private let typeLimit = 1500

    func paste(_ text: String) {
        if text.count <= typeLimit { type(text) } else { pasteViaClipboard(text) }
    }

    func type(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 20, units.count)])
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { return }
            chunk.withUnsafeBufferPointer { p in
                down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: p.baseAddress)
                up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: p.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(3000)
            i += 20
        }
    }

    func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        sendCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard pb.string(forType: .string) == text else { return }
            pb.clearContents()
            if let old { pb.setString(old, forType: .string) }
        }
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
