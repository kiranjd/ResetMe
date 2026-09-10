import AppKit
import SwiftUI

let suite = "reset.scene-check." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set(["barR": 0.58, "barG": 0.39, "barB": 0.18, "resetR": 0.18, "curve": 0.4], forKey: "opticalScene.v1")
let settings = SceneSettings(defaults: defaults)
precondition(settings.rgb("bar") == [96.0/255, 108.0/255, 56.0/255])
precondition(settings.rgb("reset") == [221.0/255, 161.0/255, 94.0/255])
precondition(settings["curve"] == 0.4)
precondition(defaults.dictionary(forKey: "opticalScene.beforeLeafPalette.v1")?["barR"] as? Double == 0.58)
settings.setColor("bar", .blue)
precondition(SceneSettings(defaults: defaults).rgb("bar") == settings.rgb("bar"))
settings.reset(group: "Glass bars")

for parameter in SceneSettings.parameters {
    settings.set(parameter.id, parameter.range.upperBound + 100)
    precondition(settings[parameter.id] == parameter.range.upperBound)
    settings.set(parameter.id, parameter.range.lowerBound - 100)
    precondition(settings[parameter.id] == parameter.range.lowerBound)
    settings.set(parameter.id, .nan)
    precondition(settings[parameter.id].isFinite)
    settings.set(parameter.id, parameter.initial)
}
settings.set("curve", 0.4)
settings.set("dotSize", 3.2)
settings.setColor("dot", .red)
settings.setColor("bar", .blue)
let dotBefore = settings.rgb("dot")
let restored = SceneSettings(defaults: defaults)
precondition(restored["curve"] == 0.4 && restored["dotSize"] == 3.2)
restored.reset(group: "Glass bars")
precondition(restored["curve"] == 0.12 && restored["dotSize"] == 3.2)
precondition(restored.rgb("bar") == [96.0/255, 108.0/255, 56.0/255])
precondition(restored.rgb("dot") == dotBefore)
let savedDot = restored.rgb("dot")
let savedBar = restored.rgb("bar")
let savedCurve = restored["curve"]
restored.applyReflectionTune()
precondition(restored.rgb("dot") == savedDot && restored.rgb("bar") == savedBar)
precondition(restored["curve"] == savedCurve && restored["softWidth"] == 0.32)
restored.reset()
precondition(restored.values.isEmpty)
let lighting = SceneLight(restored)
precondition(GlassSceneOptics.fresnel(0.1) > GlassSceneOptics.fresnel(1))
for nx in stride(from: -0.99, through: 0.99, by: 0.03) {
    let result = GlassSceneOptics.reflection(nx: nx, ny: 0, nz: sqrt(1-nx*nx), point: .zero, light: NSPoint(x: 50, y: 30), lighting: lighting)
    precondition(result.isFinite && result >= 0)
}
let faceA = GlassSceneOptics.paneReflection(nx: -0.1, ny: 0, nz: sqrt(0.99), point: .zero, light: NSPoint(x: 0, y: 0), lighting: lighting, width: 0.18)
let faceB = GlassSceneOptics.paneReflection(nx: -0.1, ny: 0, nz: sqrt(0.99), point: .zero, light: NSPoint(x: 120, y: 20), lighting: lighting, width: 0.18)
precondition(faceA.isFinite && faceB.isFinite && abs(faceA-faceB)>0.000001)
var report = [UInt8](repeating: 0, count: 22)
func put(_ offset: Int, _ value: Int32) {
    let bits = UInt32(bitPattern: value)
    for i in 0..<4 { report[offset+i] = UInt8(truncatingIfNeeded: bits >> (i*8)) }
}
put(14, -65536)
let level = report.withUnsafeBufferPointer { TiltVector.decode($0) }!
precondition(abs(level.roll)<0.0001 && abs(level.pitch)<0.0001)
put(6, 32768); put(14, -56756)
let tilted = report.withUnsafeBufferPointer { TiltVector.decode($0) }!
precondition(abs(tilted.roll*180 / .pi-30)<0.01)
precondition([UInt8](repeating: 0, count: 21).withUnsafeBufferPointer { TiltVector.decode($0) } == nil)
let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 348, height: 260), styleMask: [.borderless], backing: .buffered, defer: false)
let root = NSView(frame: NSRect(x: 0, y: 0, width: 348, height: 260))
window.contentView = root
let surface = MatteSurfaceView(frame: root.bounds)
root.addSubview(surface)
let bar = GlassLightingView(frame: NSRect(x: 110, y: 80, width: 19, height: 58))
root.addSubview(bar)
func pixels() -> [UInt8] {
    let rep = bar.bitmapImageRepForCachingDisplay(in: bar.bounds)!
    bar.cacheDisplay(in: bar.bounds, to: rep)
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
}
precondition(surface.snapshotForGlass() != nil)
let textured = pixels()
MatteSurfaceView.current = nil
let plain = pixels()
let changed = zip(textured, plain).filter { $0 != $1 }.count
precondition(changed > 100, "Backdrop was not sampled")
bar.stop(); surface.setActive(false)
print("PASS: \(SceneSettings.parameters.count) setting bounds; persistence; section reset; colors; accelerometer decode and 30-degree tilt; finite optical response; native backdrop sampling (\(changed) channels)")
