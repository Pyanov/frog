import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = PetPanel()
    let recorder = AudioRecorder()
    let hotkey = HotkeyMonitor()
    let paster = Paster()
    lazy var meeting = MeetingRecorder(mic: recorder)
    lazy var hub = HubController(app: self)
    lazy var wander = Wander(panel: panel)
    let voice = PetVoice()
    let brain = Brain()
    lazy var statusBar = StatusBar(app: self)
    private var talking = false
    private(set) var engine: Transcriber = AppleTranscriber()
    private var levelTimer: Timer?
    private var listening = false
    private var engineLoading = false
    private var hasWoken = false
    private var demoTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        panel.show()
        _ = statusBar
        panel.onRightClick = { [weak self] in self?.hub.toggle() }
        panel.onLoaded = { [weak self] in
            self?.panel.js("pet.setState('loading')")
            self?.applySoundsPref()
            self?.panel.webView.evaluateJavaScript("pet.name || 'frog'") { v, _ in if let n = v as? String { self?.brain.petName = n } }
        }
        Task { await brain.prepare() }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for var r in Mind.shared.dueNow {
                    r.done = true; Mind.shared.update(r)
                    self.panel.js("pet.setState('done')")
                    self.voice.say("Ribbit. You asked me to remind you: \(r.text).", force: true)
                }
            }
        }
        UserDefaults.standard.register(defaults: ["sounds": true, "wander": true, "voiceOn": true, "voiceReadBack": false, "voiceName": "Grandpa", "brainOn": true, "chattiness": "some", "brainModel": Brain.defaultTier])
        Permissions.requestMicrophone()
        Permissions.promptAccessibilityIfNeeded()
        hotkey.onPress = { [weak self] in self?.startListening() }
        hotkey.onRelease = { [weak self] in self?.stopListening() }
        hotkey.onTalkPress = { [weak self] in self?.startTalk() }
        hotkey.onTalkRelease = { [weak self] in self?.stopTalk() }
        hotkey.start()
        CursorTracker.shared.onMove = { [weak self] nx, ny in self?.panel.js("pet.lookAt(\(nx),\(ny))") }
        CursorTracker.shared.start(panel: panel)
        meeting.onStateChange = { [weak self] s in
            self?.panel.js("pet.setState('\(s)')")
            if s == "noting" { self?.voice.notesStarted() }
            if s == "done", let n = Store.shared.notes.first { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.voice.notesReady(title: n.title) } }
        }
        meeting.engineProvider = { [weak self] in self?.engine ?? AppleTranscriber() }
        meeting.dictationActive = { [weak self] in self?.listening ?? false }
        selectEngine(UserDefaults.standard.string(forKey: "engine") ?? "apple")
        wander.enabled = UserDefaults.standard.bool(forKey: "wander")
        wander.isBusy = { [weak self] in
            guard let self else { return true }
            return self.listening || self.meeting.isRecording || self.meeting.isProcessing || self.hub.isVisible || self.engineLoading
        }
        wander.onVelocity = { [weak self] x, y in self?.panel.js("pet.setVelocity && pet.setVelocity(\(x),\(y))") }
        panel.onGrab = { [weak self] in self?.wander.pause(seconds: 30); self?.voice.grabbed() }
        voice.onTalking = { [weak self] on in self?.panel.js("pet.setTalking && pet.setTalking(\(on))") }
        if CommandLine.arguments.contains("--demo") { runDemo() }
        if CommandLine.arguments.contains("--hub") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.hub.show() } }
    }

    func applyBrainPref() { Task { await brain.prepare() } }

    func applyWanderPref() { wander.enabled = UserDefaults.standard.bool(forKey: "wander") }

    func applySoundsPref() {
        panel.js("pet.setSounds(\(UserDefaults.standard.bool(forKey: "sounds")))")
    }

    // MARK: engine
    func selectEngine(_ id: String) {
        let selectedID = id == "parakeet" && ParakeetTranscriber.isSupported ? id : "apple"
        UserDefaults.standard.set(selectedID, forKey: "engine")
        engine = (selectedID == "parakeet") ? ParakeetTranscriber() : AppleTranscriber()
        Task { await warmEngine() }
    }
    @MainActor private func warmEngine() async {
        panel.js("pet.setState('loading')")
        engineLoading = true
        defer { engineLoading = false }
        do {
            try await engine.prepare()
            panel.js("pet.setState('idle')")
            if !hasWoken { hasWoken = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.voice.woke() } }
        } catch {
            NSLog("engine prepare failed: \(error)")
            panel.js("pet.setState('confused')")
        }
    }

    // MARK: push to talk
    func startListening() {
        guard !listening, !meeting.isRecording else { return }
        listening = true
        voice.stop()
        do { try recorder.start() } catch {
            NSLog("mic start failed: \(error)")
            listening = false
            panel.js("pet.setState('confused')")
            return
        }
        panel.js("pet.setState('listening')")
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.panel.js("pet.setLevel(\(self.recorder.level))")
        }
    }

    func stopListening() {
        guard listening else { return }
        listening = false
        levelTimer?.invalidate(); levelTimer = nil
        let samples = recorder.stop()
        guard samples.count > 16000 / 3 else {      // shorter than ~0.3s: treat as an accidental tap
            panel.js("pet.setState('idle')")
            return
        }
        panel.js("pet.setState('thinking')")
        let engine = self.engine
        engine.vocabulary = Store.shared.vocabulary.words
        Task {
            do {
                let raw = try await engine.transcribe(samples)
                await MainActor.run {
                    let text = Store.shared.applyReplacements(raw)
                    if text.isEmpty { panel.js("pet.setState('idle')"); voice.heardNothing(); return }
                    panel.js("pet.setState('done')")
                    paster.paste(text + " ")
                    Store.shared.recordDictation(text)
                    if brain.enabled, brain.isReady, Double.random(in: 0...1) < brain.chattiness {
                        Task { [weak self] in
                            guard let self, let line = await self.brain.react(toDictation: text) else { return }
                            self.voice.say(line)
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.voice.dictated(text) }
                    }
                }
            } catch {
                NSLog("transcribe failed: \(error)")
                await MainActor.run { panel.js("pet.setState('confused')") }
            }
        }
    }

    // MARK: talk to the pet (hold right Option)
    func startTalk() {
        guard !listening, !talking, !meeting.isRecording else { return }
        talking = true
        voice.stop()
        do { try recorder.start() } catch { talking = false; panel.js("pet.setState('confused')"); return }
        panel.js("pet.setState('listening')")
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.panel.js("pet.setLevel(\(self.recorder.level))")
        }
    }

    func stopTalk() {
        guard talking else { return }
        talking = false
        levelTimer?.invalidate(); levelTimer = nil
        let samples = recorder.stop()
        guard samples.count > 16000 / 3 else { panel.js("pet.setState('idle')"); return }
        panel.js("pet.setState('thinking')")
        let engine = self.engine
        Task {
            do {
                let said = try await engine.transcribe(samples)
                await MainActor.run {
                    if said.isEmpty { panel.js("pet.setState('idle')"); voice.heardNothing(); return }
                    if !brain.enabled || !brain.isReady {
                        panel.js("pet.setState('done')")
                        voice.say(brain.status.hasPrefix("downloading") ? "Ribbit. My brain is still downloading, \(brain.status.dropFirst(12))." : "Ribbit? I heard you, but my brain is off. Turn it on in the Me tab.", force: true)
                        return
                    }
                }
                let reply = await brain.chat(said)
                await MainActor.run {
                    panel.js("pet.setState('done')")
                    voice.say(reply ?? "Ribbit.", force: true)
                }
            } catch {
                await MainActor.run { panel.js("pet.setState('confused')") }
            }
        }
    }

    // MARK: demo (cycles states so the pet can be screenshotted)
    private func runDemo() {
        let states = ["idle", "listening", "thinking", "done", "noting", "confused", "sleeping"]
        var i = 0
        var t: Double = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            t += 1.0 / 30.0
            if t >= 4 { t = 0; i = (i + 1) % states.count; self.panel.js("pet.setState('\(states[i])')") }
            if states[i] == "listening" { self.panel.js("pet.setLevel(\(abs(sin(t * 6)) * 0.8))") }
        }
    }
}
