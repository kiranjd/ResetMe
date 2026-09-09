import Foundation
import CoreGraphics

/// One reversible timeline drives the window, silhouette, label, and content.
public enum IslandMotion {
    /// Unit-mass critically damped attachment: stiffness = omega², damping = 2 omega.
    /// Endpoints attach first; the middle has lower stiffness, producing a short elastic bow.
    public static func latch(elapsed: Double, fraction: Double) -> Double {
        let omega = 58 - 16 * sin(.pi * unit(fraction))
        let time = max(0, elapsed)
        return unit(1 - (1 + omega * time) * exp(-omega * time))
    }
    public static let wingWidth: CGFloat = 32
    public static func canvasFrame(_ notch: CGRect) -> CGRect {
        CGRect(x: notch.midX - 174, y: notch.maxY - 600, width: 348, height: 600)
    }
    public static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
    public static func smooth(_ value: Double) -> Double {
        let t = unit(value)
        return t * t * (3 - 2 * t)
    }
    public static func breadth(_ progress: Double) -> Double {
        return travel(progress)
    }
    public static func depth(_ progress: Double) -> Double { travel(progress) }
    public static func straighten(_ p: Double) -> Double { smooth(p / 0.25) }
    public static func travel(_ p: Double) -> Double { smooth((p - 0.25) / 0.50) }
    public static func compactOpacity(_ progress: Double) -> Double { 1 - smooth(progress / 0.28) }
    public static func content(_ progress: Double) -> Double { smooth((progress - 0.78) / 0.22) }
    public static func row(_ progress: Double, index: Int) -> Double {
        1
    }
    public static func compactFrame(_ notch: CGRect) -> CGRect {
        CGRect(x: notch.minX - wingWidth, y: notch.minY, width: notch.width + wingWidth, height: notch.height)
    }
    public static func frame(notch: CGRect, expandedHeight: CGFloat, progress: Double) -> CGRect {
        let w = breadth(progress), h = depth(progress)
        let collapsed = compactFrame(notch)
        let width = collapsed.width + (348 - collapsed.width) * w
        let height = collapsed.height + (expandedHeight - collapsed.height) * h
        let x = collapsed.minX + (notch.midX - 174 - collapsed.minX) * w
        return CGRect(x: x, y: notch.maxY - height, width: width, height: height)
    }
    /// Analytic critically damped spring; carries velocity through direction changes.
    public static func spring(value: Double, velocity: Double, target: Double, elapsed: Double, frequency: Double) -> (value: Double, velocity: Double) {
        let delta = value - target
        let coefficient = velocity + frequency * delta
        let decay = exp(-frequency * elapsed)
        return (target + (delta + coefficient * elapsed) * decay,
                (velocity - frequency * coefficient * elapsed) * decay)
    }
}
