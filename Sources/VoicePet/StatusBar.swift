import AppKit

/// The menu bar item next to Wi-Fi and battery: show/hide the pet, open the hub, toggles, quit.
@MainActor
final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var app: AppDelegate?
    private let menu = NSMenu()

    init(app: AppDelegate) {
        self.app = app
        super.init()
        item.button?.image = Self.frogGlyph()
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Frog"
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app else { return }
        let visible = app.panel.isVisible
        menu.addItem(make(visible ? "Hide the frog" : "Show the frog", #selector(toggleVisible), key: "h"))
        menu.addItem(make("Notes & settings…", #selector(openHub), key: ","))
        menu.addItem(.separator())
        let wander = make("Wanders around", #selector(toggleWander), key: "")
        wander.state = UserDefaults.standard.bool(forKey: "wander") ? .on : .off
        menu.addItem(wander)
        let voice = make("Talks back", #selector(toggleVoice), key: "")
        voice.state = UserDefaults.standard.bool(forKey: "voiceOn") ? .on : .off
        menu.addItem(voice)
        let sounds = make("Sounds", #selector(toggleSounds), key: "")
        sounds.state = UserDefaults.standard.bool(forKey: "sounds") ? .on : .off
        menu.addItem(sounds)
        menu.addItem(.separator())
        menu.addItem(make("Quit Frog", #selector(quit), key: "q"))
    }

    private func make(_ title: String, _ sel: Selector, key: String) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.target = self
        return m
    }

    @objc private func toggleVisible() {
        guard let app else { return }
        if app.panel.isVisible { app.panel.orderOut(nil) } else { app.panel.show() }
    }
    @objc private func openHub() { app?.hub.show() }
    @objc private func toggleWander() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "wander"), forKey: "wander"); app?.applyWanderPref()
    }
    @objc private func toggleVoice() { UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "voiceOn"), forKey: "voiceOn") }
    @objc private func toggleSounds() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "sounds"), forKey: "sounds"); app?.applySoundsPref()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    /// A tiny frog head: wide face with two eye bumps, drawn as a template image.
    static func frogGlyph() -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let face = NSBezierPath(ovalIn: NSRect(x: 1, y: 0.5, width: 18, height: 11))
            face.fill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: 8, width: 6, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11, y: 8, width: 6, height: 6)).fill()
            NSColor.clear.setFill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 5, y: 9.5, width: 2.4, height: 2.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.6, y: 9.5, width: 2.4, height: 2.4)).fill()
            NSBezierPath(rect: NSRect(x: 5.5, y: 3.6, width: 9, height: 1.1)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
