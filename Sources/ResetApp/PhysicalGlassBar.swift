import AppKit
import SwiftUI
import Combine

/// Palette-colored frosted glass with diffuse transmission and a narrow polished rim.
/// Shared Mac-driven light shifts the broad highlight across the face.
struct PhysicalGlassBar: NSViewRepresentable {
    var emphasized: Bool
    func makeNSView(context: Context) -> GlassLightingView { GlassLightingView() }
    func updateNSView(_ view: GlassLightingView, context: Context) {
        if view.emphasized != emphasized { view.emphasized = emphasized; view.needsDisplay = true }
    }
    static func dismantleNSView(_ view: GlassLightingView, coordinator: ()) { view.stop() }
}

final class GlassLightingView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var emphasized = false
    private var settingsObserver: AnyCancellable?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        settingsObserver = SceneSettings.shared.$values.dropFirst().sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var timer: Timer?
    private var lastPointer = NSPoint(x: -9999, y: -9999)
    private var lastRevision = -1
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            let revision = MatteSurfaceView.current?.surfaceRevision ?? 0
            if hypot(p.x - self.lastPointer.x, p.y - self.lastPointer.y) > 0.5 || revision != self.lastRevision {
                self.lastPointer = p; self.lastRevision = revision; self.needsDisplay = true
            }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let w = max(1, Int(bounds.width * scale)), h = max(1, Int(bounds.height * scale))
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        let surface = MatteSurfaceView.current
        let origin = surface.map { convert(NSPoint.zero, to: $0) } ?? .zero
        let light = surface?.opticalLight ?? NSPoint(x: 170, y: 110)
        let shift = tanh((light.x-origin.x-bounds.midX)/200)
        let height = Double(bounds.height), width = Double(bounds.width)
        let tint = SceneSettings.shared.rgb("bar").map { min(1, $0 * 1.35) }
        let transmission = SceneSettings.shared.rgb("accent")
        let rim = transmission.map { $0 * 0.55 + 0.45 }
        // Broad diffuse body and polished rim inherit the current palette.
        // The matte body intentionally obscures the busy mesh behind it.
        for y in 0..<h {
            let py = (Double(y)+0.5)/scale
            for x in 0..<w {
                let px = (Double(x)+0.5)/scale, u = px/width
                let edge = min(px,width-px)
                let side = exp(-pow(edge/0.65,2))
                let top = exp(-pow(py/0.7,2))
                let bottom = exp(-pow((height-py)/max(1.5,min(7,height*0.22)),2))
                let broad = exp(-pow((u-(0.30+shift*0.14))/0.32,2))
                let glint = exp(-pow((px-(1.5+shift*0.4))/1.0,2))*0.15
                let body = 0.82+0.16*broad+0.12*bottom
                let highlight = min(0.75,side*0.30+top*0.63+glint)
                let index = (y*w+x)*4
                for channel in 0..<3 {
                    let base = tint[channel]*body+transmission[channel]*bottom*0.15
                    let value = base*(1-highlight)+rim[channel]*highlight
                    bytes[index+channel] = UInt8(min(1,max(0,value*(emphasized ? 1.06 : 1)))*255)
                }
            }
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData), let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
