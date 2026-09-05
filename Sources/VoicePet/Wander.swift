import AppKit

/// Cruises the pet's window around the screen: a heading that drifts, steers away from edges, and now and then rests.
@MainActor
final class Wander {
    private weak var panel: NSPanel?
    private var timer: Timer?
    private var heading: Double = .random(in: 0..<(2 * .pi))
    private var turnRate: Double = 0
    private var restUntil = Date().addingTimeInterval(3)
    private var cruiseUntil = Date().addingTimeInterval(3 + .random(in: 20...60))
    private var pausedUntil = Date.distantPast
    private var lastVel = (0.0, 0.0)
    var enabled = true { didSet { if !enabled { emit(0, 0) } } }
    var isBusy: () -> Bool = { false }
    var onVelocity: ((Double, Double) -> Void)?
    private let speed: CGFloat = 34          // points per second

    init(panel: NSPanel) {
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause(seconds: Double) {
        pausedUntil = Date().addingTimeInterval(seconds)
        emit(0, 0)
    }

    private func emit(_ x: Double, _ y: Double) {
        guard abs(x - lastVel.0) > 0.01 || abs(y - lastVel.1) > 0.01 else { return }
        lastVel = (x, y)
        onVelocity?(x, y)
    }

    private func tick() {
        guard enabled, let panel, Date() > pausedUntil, !isBusy() else { emit(0, 0); return }
        let now = Date()
        if now < restUntil { emit(0, 0); return }
        if now > cruiseUntil {                       // take a break, then cruise again
            restUntil = now.addingTimeInterval(.random(in: 4...12))
            cruiseUntil = restUntil.addingTimeInterval(.random(in: 25...70))
            heading = .random(in: 0..<(2 * .pi))
            emit(0, 0); return
        }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let f = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        let w = panel.frame.width, h = panel.frame.height
        let cur = panel.frame.origin
        // wander: heading drifts with a little random turning; steer back toward the middle near the edges
        turnRate += (Double.random(in: -1...1) * 1.2 - turnRate * 0.9) * (1.0 / 30.0)
        heading += turnRate * (1.0 / 30.0)
        let cx = f.midX - w / 2, cy = f.midY - h / 2
        let ex = Double((cur.x - cx) / (f.width / 2 - w / 2)), ey = Double((cur.y - cy) / (f.height / 2 - h / 2))   // -1..1
        let toCenter = atan2(-ey, -ex)
        let edge = max(abs(ex), abs(ey))
        if edge > 0.7 {
            var d = toCenter - heading
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            heading += d * min(1, (edge - 0.7) * 0.25)
        }
        let dx = cos(heading), dy = sin(heading) * 0.55        // fish glide more sideways than up and down
        let step = speed / 30.0
        var nx = cur.x + CGFloat(dx) * step, ny = cur.y + CGFloat(dy) * step
        nx = max(f.minX, min(nx, f.maxX - w)); ny = max(f.minY, min(ny, f.maxY - h))
        panel.setFrameOrigin(NSPoint(x: nx, y: ny))
        emit(dx, dy)
    }
}
