import AppKit
import SwiftUI

struct SceneParameter: Identifiable {
    let id: String
    let label: String
    let group: String
    let initial: Double
    let range: ClosedRange<Double>
    let step: Double
    init(_ id: String, _ label: String, _ group: String, _ initial: Double, _ low: Double, _ high: Double, _ step: Double = 0.01) {
        self.id = id; self.label = label; self.group = group; self.initial = initial; self.range = low...high; self.step = step
    }
}

final class SceneSettings: ObservableObject {
    static let shared = SceneSettings()
    static let groups = ["Glass bars", "Dots", "Lighting", "Pointer", "Background", "Chart & reset"]
    static let parameters: [SceneParameter] = [
        .init("curve", "Center curvature", "Glass bars", 0.12, 0, 0.8),
        .init("edgeCurve", "Edge curvature", "Glass bars", 0.58, 0, 0.95),
        .init("bevel", "Border width", "Glass bars", 2.2, 0.3, 9, 0.1),
        .init("depth", "Glass thickness", "Glass bars", 2.2, 0, 16, 0.1),
        .init("zoom", "Center magnification", "Glass bars", 1.10, 0.7, 1.8),
        .init("ior", "Refraction", "Glass bars", 1.5, 1, 2.4),
        .init("transmission", "Backdrop visibility", "Glass bars", 1.6, 0, 4),
        .init("body", "Tint density", "Glass bars", 1, 0, 2),
        .init("barReflection", "Reflection strength", "Glass bars", 1, 0, 3),
        .init("faceReflection", "Face reflection", "Glass bars", 0.35, 0, 3),
        .init("faceWidth", "Face reflection width", "Glass bars", 0.18, 0.05, 0.6),
        .init("barRadius", "Corner radius", "Glass bars", 4, 0, 12, 0.25),
        .init("mesh", "Physical dot mesh", "Dots", 1, 0, 1, 1),
        .init("meshThreshold", "Shake to break (g)", "Dots", 0.45, 0.15, 2, 0.05),
        .init("meshStiffness", "Mesh stiffness", "Dots", 90, 25, 240, 5),
        .init("meshLinks", "Mesh link visibility", "Dots", 0.12, 0, 0.5),
        .init("meshGravity", "Loose dot gravity", "Dots", 550, 100, 1000, 10),
        .init("meshBounce", "Loose dot bounce", "Dots", 0.35, 0, 0.9, 0.05),
        .init("dotSize", "Size", "Dots", 2.1, 0.5, 5, 0.1),
        .init("dotSpacing", "Spacing", "Dots", 6, 4, 18, 0.25),
        .init("dotOpacity", "Opacity", "Dots", 0.74, 0, 1),
        .init("dotCurve", "Curvature", "Dots", 0.50, 0, 0.95),
        .init("dotFlat", "Flat center", "Dots", 0.72, 0, 0.95),
        .init("dotReflection", "Reflection strength", "Dots", 1, 0, 4),
        .init("dotBody", "Body brightness", "Dots", 1, 0, 3),
        .init("dotVariation", "Brightness variation", "Dots", 0.12, 0, 0.5),
        .init("dotLens", "Hover magnification", "Dots", 0.30, 0, 2),
        .init("edgeCompression", "Perimeter compression", "Dots", 24, 1, 48, 1),
        .init("lightStrength", "Light intensity", "Lighting", 1, 0, 3),
        .init("softbox", "Broad reflection", "Lighting", 3, 0, 10, 0.1),
        .init("softWidth", "Reflection softness", "Lighting", 0.23, 0.04, 0.8),
        .init("rimLight", "Side reflection", "Lighting", 1.5, 0, 8, 0.1),
        .init("topLight", "Top reflection", "Lighting", 1.3, 0, 8, 0.1),
        .init("lightX", "Light horizontal offset", "Lighting", 0, -350, 350, 1),
        .init("lightY", "Light vertical offset", "Lighting", 0, -250, 250, 1),
        .init("macTilt", "Use real Mac tilt", "Lighting", 1, 0, 1, 1),
        .init("tiltGain", "Tilt response", "Lighting", 1, 0, 3),
        .init("ropeLength", "Lamp suspension length", "Lighting", 120, 60, 240, 1),
        .init("lampDamping", "Lamp settling", "Lighting", 1.8, 0.4, 5, 0.1),
        .init("lampSwing", "Lamp swing limit", "Lighting", 0.24, 0.05, 0.5),
        .init("follow", "Cursor interaction", "Pointer", 1, 0, 1, 1),
        .init("dotMotion", "Move dots", "Pointer", 1, 0, 1, 1),
        .init("displacement", "Dot displacement", "Pointer", 2, 0, 12, 0.1),
        .init("velocity", "Dot drift", "Pointer", 0.3, 0, 2),
        .init("influence", "Influence radius", "Pointer", 58, 15, 160, 1),
        .init("ease", "Follow speed", "Pointer", 0.25, 0.05, 1),
        .init("glow", "Surface glow", "Pointer", 0.016, 0, 0.15, 0.001),
        .init("streak", "Surface light streak", "Pointer", 0.025, 0, 0.2, 0.001),
        .init("background", "Surface brightness", "Background", 1, 0, 3),
        .init("warmth", "Warm shading", "Background", 0.08, 0, 0.5),
        .init("contentShade", "Shade behind text", "Background", 0.94, 0, 1),
        .init("chartShade", "Shade behind chart", "Background", 0.55, 0, 1),
        .init("surfaceRim", "Outer edge shine", "Background", 1, 0, 4),
        .init("barWidth", "Bar width", "Chart & reset", 19, 6, 21, 0.5),
        .init("barHeight", "Bar height", "Chart & reset", 58, 24, 58, 1),
        .init("selection", "Selected day glow", "Chart & reset", 0.25, 0, 0.7),
        .init("resetGap", "Reset spacing", "Chart & reset", 12, 0, 40, 1),
        .init("resetWidth", "Reset line width", "Chart & reset", 3, 1, 7, 0.25),
        .init("resetSize", "Reset circle size", "Chart & reset", 17, 12, 26, 0.5)
    ]
    @Published private(set) var values: [String: Double]
    private let defaults: UserDefaults
    private static let storageKey = "opticalScene.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.dictionary(forKey: Self.storageKey)?.compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
        values = values.filter { $0.value.isFinite }
        if !defaults.bool(forKey: "softHangingLight.v1") {
            for (key, factor) in [("dotOpacity", 0.75), ("dotReflection", 0.65), ("barReflection", 0.8), ("faceReflection", 0.8)] {
                let baseline = values[key] ?? Self.parameters.first(where: { $0.id == key })!.initial
                values[key] = baseline * factor
            }
            defaults.set(values, forKey: Self.storageKey)
            defaults.set(true, forKey: "softHangingLight.v1")
        }
    }
    subscript(_ key: String) -> Double {
        let definition = Self.parameters.first { $0.id == key }
        let value = values[key] ?? definition?.initial ?? 0
        if let range = definition?.range { return min(range.upperBound, max(range.lowerBound, value)) }
        return value
    }
    func set(_ key: String, _ value: Double) {
        guard value.isFinite else { return }
        var next = values
        if let p = Self.parameters.first(where: { $0.id == key }) { next[key] = min(p.range.upperBound, max(p.range.lowerBound, value)) }
        else { next[key] = min(1, max(0, value)) }
        values = next
        defaults.set(next, forKey: Self.storageKey)
        if key == "macTilt" { MacTilt.shared.updateEnabled() }
    }
    func replace(_ next: [String: Double]) {
        values = next.filter { $0.value.isFinite }; defaults.set(values, forKey: Self.storageKey)
        MacTilt.shared.updateEnabled()
    }
    func applyReflectionTune() {
        // Preserve every chosen color and all geometry; tune only illumination and contrast.
        var next = values
        let adjustments: [String: Double] = [
            "lightStrength": 1.35, "softbox": 5.2, "softWidth": 0.32,
            "rimLight": 1.8, "topLight": 2.3, "barReflection": 1.25,
            "dotReflection": 1.05, "dotBody": 1.15, "dotOpacity": 0.88,
            "dotVariation": 0.18, "surfaceRim": 1.65,
            "lightX": 0, "lightY": 0, "selection": 0.25
        ]
        next.merge(adjustments) { _, new in new }
        replace(next)
    }
    func reset(group: String? = nil) {
        guard let group else { replace([:]); return }
        let keys = Self.parameters.filter { $0.group == group }.map(\.id)
        let prefixes = group == "Glass bars" ? ["bar"] : group == "Dots" ? ["dot"] : group == "Lighting" ? ["light"] : group == "Chart & reset" ? ["reset"] : group == "Background" ? ["accent", "background"] : []
        replace(values.filter { !keys.contains($0.key) })
        // Color defaults are restored separately from scalar controls.
        var next = values
        for prefix in prefixes { for suffix in ["R", "G", "B"] { next.removeValue(forKey: prefix+suffix) } }
        replace(next)
    }
    func rgb(_ name: String) -> [Double] {
        let base: [Double]
        switch name {
        case "bar": base = [0.48, 0.29, 0.17]
        case "dot": base = [0.957, 0.976, 1]
        case "accent": base = [0.86, 0.52, 0.30]
        case "background": base = [0.065, 0.065, 0.065]
        case "reset": base = [0.25, 0.78, 0.47]
        default: base = [1, 1, 1]
        }
        return zip(["R", "G", "B"], base).map { min(1, max(0, values[name+$0.0] ?? $0.1)) }
    }
    func color(_ name: String) -> Color { let c = rgb(name); return Color(.sRGB, red: c[0], green: c[1], blue: c[2]) }
    func setColor(_ name: String, _ color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
        var next = values
        for (suffix, value) in zip(["R", "G", "B"], [c.redComponent, c.greenComponent, c.blueComponent]) { next[name+suffix] = value }
        replace(next)
    }
}
