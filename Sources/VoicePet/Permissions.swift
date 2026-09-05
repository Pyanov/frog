import AVFoundation
import ApplicationServices
import Foundation

enum Permissions {
    static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func promptAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// System Settings > Keyboard > "Press 🌐 key to". 0 = Do Nothing (what we want).
    static var fnKeyDoesSomethingElse: Bool {
        let v = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int
        return (v ?? 0) != 0
    }
}
