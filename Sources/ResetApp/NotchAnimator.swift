import AppKit
import QuartzCore
import ResetCore

@MainActor final class NotchAnimator: NSObject {
    private var timer: CADisplayLink?
    weak var window: NSWindow?
    private var value = 0.0
    private var velocity = 0.0
    private var target = 0.0
    private var lastTick = 0.0
    var render: ((Double) -> Void)?
    var renderFill: ((Double) -> Void)?
    private var fill = 1.0
    private var closingElapsed = 0.0
    var renderClosingTime: ((Double) -> Void)?
    var isRunning: Bool { timer != nil }
    func move(to newTarget: Double, animated: Bool) {
        if newTarget != target { closingElapsed = 0; renderClosingTime?(0) }
        if newTarget != target { fill = newTarget == 0 ? 0 : 1; renderFill?(fill) }
        target = newTarget
        guard animated else {
            timer?.invalidate(); timer = nil; value = target; velocity = 0
            fill = 1; renderFill?(1); render?(value); return
        }
        guard abs(value - target) > 0.0001 || abs(velocity) > 0.005 else { render?(target); return }
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        guard let window else { render?(target); return }
        let next = window.displayLink(target: self, selector: #selector(step))
        timer = next
        next.add(to: .main, forMode: .common)
    }
    @objc private func step() {
        let time = CACurrentMediaTime()
        let elapsed = min(0.05, time - lastTick); lastTick = time
        if target == 0 { closingElapsed += elapsed; renderClosingTime?(closingElapsed) }
        let next = IslandMotion.spring(value: value, velocity: velocity, target: target, elapsed: elapsed / 1.12, frequency: target == 1 ? 10 : 28)
        value = IslandMotion.unit(next.value); velocity = next.velocity
        if abs(value - target) < 0.001 && abs(velocity) < 0.02 {
            value = target; velocity = 0
            timer?.invalidate(); timer = nil
        }
        render?(value)
    }
    func stop() { timer?.invalidate(); timer = nil }
}
