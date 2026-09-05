import AppKit
import WebKit

/// The pet lives in a borderless, transparent, always-on-top panel that never takes focus.
/// Left-drag moves it, right-click opens settings.
final class PetWebView: WKWebView {
    var onRightClick: (() -> Void)?
    var onGrab: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onGrab?()
        evaluateJavaScript("pet.boop()", completionHandler: nil)
        window?.performDrag(with: event)
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}

final class PetPanel: NSPanel, WKNavigationDelegate {
    static let size = NSSize(width: 320, height: 320)
    let webView: PetWebView
    var onRightClick: (() -> Void)? { didSet { webView.onRightClick = onRightClick } }
    var onGrab: (() -> Void)? { didSet { webView.onGrab = onGrab } }
    private var saveWork: DispatchWorkItem?
    var onLoaded: (() -> Void)?
    private var loaded = false
    private var pendingJS: [String] = []

    init() {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        cfg.mediaTypesRequiringUserActionForPlayback = []
        webView = PetWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: cfg)
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = self
        contentView = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("web/index.html missing from bundle")
        }
        restorePosition()
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.saveWork?.cancel()
            let w = DispatchWorkItem { UserDefaults.standard.set(NSStringFromPoint(self.frame.origin), forKey: "petOrigin") }
            self.saveWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
        }
    }

    func show() { orderFrontRegardless() }

    /// Queue JS until the page has loaded, then run on main.
    func js(_ script: String) {
        DispatchQueue.main.async {
            if self.loaded { self.webView.evaluateJavaScript(script, completionHandler: nil) }
            else { self.pendingJS.append(script) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        pendingJS.forEach { webView.evaluateJavaScript($0, completionHandler: nil) }
        pendingJS.removeAll()
        onLoaded?()
    }

    private func restorePosition() {
        if let s = UserDefaults.standard.string(forKey: "petOrigin") {
            setFrameOrigin(NSPointFromString(s))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.maxX - Self.size.width - 24, y: f.minY + 24))
        }
    }
}
