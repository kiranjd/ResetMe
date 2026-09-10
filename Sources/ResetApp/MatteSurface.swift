import AppKit
import SwiftUI
import Combine

struct MatteSurface: NSViewRepresentable {
    var active: Bool
    func makeNSView(context: Context) -> MatteSurfaceView { MatteSurfaceView() }
    func updateNSView(_ view: MatteSurfaceView, context: Context) { view.setActive(active) }
    static func dismantleNSView(_ view: MatteSurfaceView, coordinator: ()) { view.setActive(false) }
}

/// Surface-only motion: never changes layout or intercepts pointer events.
final class MatteSurfaceView: NSView {
    static weak var current: MatteSurfaceView?
    private(set) var surfaceRevision = 0
    private var opticalSnapshot: NSBitmapImageRep?
    private var opticalSize = NSSize.zero
    private var settingsObserver: AnyCancellable?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        settingsObserver = SceneSettings.shared.$values.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.dotSprites.removeAll(keepingCapacity: true)
            self.opticalSnapshot = nil; self.surfaceRevision += 1; self.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { Self.current = self }
    }
    /// Renders only our own material, never the app window or the glass above it.
    func snapshotForGlass() -> NSBitmapImageRep? {
        if let opticalSnapshot, opticalSize == bounds.size { return opticalSnapshot }
        let scale = 2.0
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        context.cgContext.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        renderSurface()
        NSGraphicsContext.restoreGraphicsState()
        opticalSnapshot = bitmap; opticalSize = bounds.size
        return bitmap
    }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var opticalLight: NSPoint {
        let settings = SceneSettings.shared
        let follows = settings["macTilt"] > 0.5 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let angle = follows ? lampAngle : 0
        let ropeLength = settings["ropeLength"]
        let point = NSPoint(x: bounds.midX+sin(angle)*ropeLength*2.5, y: 12+cos(angle)*ropeLength+sin(follows ? lampPitch : 0)*ropeLength*0.4)
        return NSPoint(x: point.x + settings["lightX"], y: point.y + settings["lightY"])
    }
    private var dotSprites: [Int: NSImage] = [:]
    private let mesh = DotMeshSimulation()
    func rebuildMesh() { mesh.rebuild(); opticalSnapshot = nil; surfaceRevision += 1; needsDisplay = true }
    func breakMesh() { mesh.breakApart(); needsDisplay = true }
    private func configureMesh() {
        let s = SceneSettings.shared
        mesh.configure(size: bounds.size, spacing: s["dotSpacing"], compression: s["edgeCompression"])
    }
    private var timer: Timer?
    private var cursor = NSPoint(x: -500, y: -500)
    private var drift = NSPoint.zero
    private var presence = 0.0
    private var lastPoint: NSPoint?
    private var lampAngle = 0.0
    private var lampVelocity = 0.0
    private var lampPitch = 0.0
    private var lampPitchVelocity = 0.0
    private var lastStepTime = ProcessInfo.processInfo.systemUptime
    func setActive(_ active: Bool) {
        guard active else { timer?.invalidate(); timer = nil; presence = 0; lastPoint = nil; needsDisplay = true; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.step() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func step() {
        guard let window else { return }
        let oldCursor = cursor, oldDrift = drift, oldPresence = presence
        let oldLampAngle = lampAngle, oldLampPitch = lampPitch
        let time = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0.001, time-lastStepTime))
        lastStepTime = time
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let settings = SceneSettings.shared
        let inside = bounds.contains(point) && settings["follow"] > 0.5
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduced && settings["macTilt"] > 0.5 {
            let limit = settings["lampSwing"]
            let target = max(-limit,min(limit,(MacTilt.shared.roll ?? 0)*settings["tiltGain"]))
            let targetPitch = max(-limit,min(limit,(MacTilt.shared.pitch ?? 0)*settings["tiltGain"]))
            // Gravity direction comes from measured Mac tilt. No cursor impulse or synthetic input.
            let gravity = 24.0, damping = 6.0
            lampVelocity += (-gravity*sin(lampAngle-target)-damping*lampVelocity)*dt
            lampPitchVelocity += (-gravity*sin(lampPitch-targetPitch)-damping*lampPitchVelocity)*dt
            lampAngle += lampVelocity*dt
            lampPitch += lampPitchVelocity*dt
            if abs(lampAngle) > limit { lampAngle = max(-limit,min(limit,lampAngle)); lampVelocity *= 0.5 }
            if abs(lampPitch) > limit { lampPitch = max(-limit,min(limit,lampPitch)); lampPitchVelocity *= 0.5 }
        } else { lampAngle = 0; lampVelocity = 0; lampPitch = 0; lampPitchVelocity = 0 }
        configureMesh()
        var meshMoved = false
        if !reduced && settings["mesh"] > 0.5, let gravity = MacTilt.shared.sceneGravity, let shake = MacTilt.shared.sceneShake {
            meshMoved = mesh.step(dt: dt, gravity: gravity, shake: shake, shock: MacTilt.shared.shock,
                threshold: settings["meshThreshold"], stiffness: settings["meshStiffness"],
                gravityScale: settings["meshGravity"], restitution: settings["meshBounce"], diameter: settings["dotSize"])
        }
        presence += ((inside ? 1.0 : 0.0) - presence) * 0.18
        if inside {
            if let lastPoint {
                drift.x = drift.x * 0.78 + max(-30, min(30, point.x - lastPoint.x)) * 0.22
                drift.y = drift.y * 0.78 + max(-30, min(30, point.y - lastPoint.y)) * 0.22
                cursor.x += (point.x - cursor.x) * (reduced ? 1 : settings["ease"])
                cursor.y += (point.y - cursor.y) * (reduced ? 1 : settings["ease"])
            } else { cursor = point }
            lastPoint = point
        } else { lastPoint = nil; drift.x *= 0.8; drift.y *= 0.8 }
        if meshMoved || abs(lampPitch-oldLampPitch) > 0.00001 || abs(lampAngle-oldLampAngle) > 0.00001 || hypot(cursor.x - oldCursor.x, cursor.y - oldCursor.y) > 0.01 || hypot(drift.x - oldDrift.x, drift.y - oldDrift.y) > 0.01 || abs(presence - oldPresence) > 0.001 { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        surfaceRevision += 1
        opticalSnapshot = nil
        renderSurface()
    }
    private func renderSurface() {
        let settings = SceneSettings.shared
        let brightness = settings["background"]
        let backgroundColor = settings.rgb("background")
        let influenceRadius = settings["influence"]
        let displacement = settings["displacement"], velocity = settings["velocity"]
        let dotSize = settings["dotSize"], dotLens = settings["dotLens"]
        let dotOpacity = settings["dotOpacity"], variation = settings["dotVariation"]
        let light = opticalLight
        NSGradient(colors: [0.385, 1.0, 0.538].map { factor in
            NSColor(srgbRed: min(1, backgroundColor[0]*brightness*factor), green: min(1, backgroundColor[1]*brightness*factor), blue: min(1, backgroundColor[2]*brightness*factor), alpha: 1)
        })?.draw(in: bounds, angle: 55)
        // Broad low-contrast material shading, not a glass slab.
        NSGradient(starting: NSColor(red: 96.0/255, green: 108.0/255, blue: 56.0/255, alpha: settings["warmth"]), ending: .clear)?.draw(in: NSRect(x: -100, y: -90, width: bounds.width + 140, height: 310), relativeCenterPosition: .zero)
        if presence > 0.005 {
            NSGradient(colors: [NSColor(white: 1, alpha: settings["glow"] * presence), NSColor(red: 221.0/255, green: 161.0/255, blue: 94.0/255, alpha: settings["glow"] * presence), .clear])?.draw(in: NSRect(x: cursor.x - 95, y: cursor.y - 32, width: 190, height: 64), relativeCenterPosition: .zero)
            NSGradient(starting: NSColor(white: 1, alpha: settings["streak"] * presence), ending: .clear)?.draw(in: NSRect(x: cursor.x - 40, y: cursor.y - 4, width: 80, height: 8), relativeCenterPosition: .zero)
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || settings["dotMotion"] < 0.5
        configureMesh()
        let physical = settings["mesh"] > 0.5
        var rendered: [(CGPoint, Double, Double)] = []
        rendered.reserveCapacity(mesh.particles.count)
        for particle in mesh.particles {
            var point = physical ? particle.position : particle.home
            let dx = point.x-cursor.x, dy = point.y-cursor.y, distance = hypot(dx,dy)
            let influence = exp(-(distance*distance)/(2*influenceRadius*influenceRadius))*presence
            let lens = influence*(1+max(0,1-point.y/120)*0.3)
            if !reduced && (!physical || !mesh.broken) {
                point.x += (dx/max(12,distance)*displacement+drift.x*velocity)*lens
                point.y += (dy/max(12,distance)*displacement+drift.y*velocity)*lens
            }
            let rim = max(0,1-min(point.x,bounds.width-point.x,bounds.height-point.y)/20)
            rendered.append((point,lens,rim))
        }
        if physical && settings["meshLinks"] > 0 {
            let path = NSBezierPath()
            for link in mesh.links where link.active {
                path.move(to: rendered[link.a].0); path.line(to: rendered[link.b].0)
            }
            NSColor(white: 0.8,alpha: settings["meshLinks"]*0.12).setStroke()
            path.lineWidth = 0.4; path.stroke()
        }
        for (index, item) in rendered.enumerated() {
            let point = item.0, lens = item.1, rim = item.2
            let diameter = dotSize + (reduced || (physical && mesh.broken) ? 0 : lens*dotLens)
            let noise = Double((index*73)%101)/100
            let qx = Int(max(-24,min(24,((light.x-point.x)/24).rounded())))
            let qy = Int(max(-24,min(24,((light.y-point.y)/24).rounded())))
            let key = (qx+24)*49+qy+24
            if dotSprites[key] == nil {
                dotSprites[key] = GlassSceneOptics.dotImage(point: .zero,light: NSPoint(x: qx*24,y: qy*24))
            }
            dotSprites[key]?.draw(in: NSRect(x: point.x-diameter/2,y: point.y-diameter/2,width: diameter,height: diameter),
                from: .zero,operation: .sourceOver,
                fraction: min(1,dotOpacity*(0.84+noise*variation+lens*0.14+rim*0.10)*(0.42+0.58*exp(-pow(Double(min(point.x,bounds.width-point.x))/35,2)))),respectFlipped: true,hints: nil)
        }
        // Open-sided bevel: no rounded top stroke inside the flat-topped shell.
        let bevel = NSBezierPath()
        let w = bounds.width, h = bounds.height
        bevel.move(to: NSPoint(x: 0.8, y: 0))
        bevel.line(to: NSPoint(x: 0.8, y: h - 18))
        bevel.curve(to: NSPoint(x: 18, y: h - 0.8), controlPoint1: NSPoint(x: 0.8, y: h - 8), controlPoint2: NSPoint(x: 8, y: h - 0.8))
        bevel.line(to: NSPoint(x: w - 18, y: h - 0.8))
        bevel.curve(to: NSPoint(x: w - 0.8, y: h - 18), controlPoint1: NSPoint(x: w - 8, y: h - 0.8), controlPoint2: NSPoint(x: w - 0.8, y: h - 8))
        bevel.line(to: NSPoint(x: w - 0.8, y: 0))
        let rimStrength = settings["surfaceRim"]
        // A continuous hairline joins the upper sides, lower corners, and bottom edge.
        NSColor(white: 0.92, alpha: min(0.65, 0.15*rimStrength)).setStroke()
        bevel.lineWidth = 0.85; bevel.stroke()
        let shine = NSColor(white: 1, alpha: min(0.5, (0.09 + presence*0.025)*rimStrength))
        NSGradient(starting: shine, ending: .clear)?.draw(in: NSRect(x: 0.8, y: 0, width: 4.5, height: max(0, h-18)), angle: 0)
        NSGradient(starting: .clear, ending: shine)?.draw(in: NSRect(x: w-5.3, y: 0, width: 4.5, height: max(0, h-18)), angle: 0)
        // Clip a reflected strip to the whole U-shaped edge, including both curved corners.
        if let context = NSGraphicsContext.current?.cgContext {
            let rim = CGMutablePath()
            rim.move(to: CGPoint(x: 1.3, y: 0))
            rim.addLine(to: CGPoint(x: 1.3, y: h-18))
            rim.addCurve(to: CGPoint(x: 18, y: h-1.3), control1: CGPoint(x: 1.3, y: h-8), control2: CGPoint(x: 8, y: h-1.3))
            rim.addLine(to: CGPoint(x: w-18, y: h-1.3))
            rim.addCurve(to: CGPoint(x: w-1.3, y: h-18), control1: CGPoint(x: w-8, y: h-1.3), control2: CGPoint(x: w-1.3, y: h-8))
            rim.addLine(to: CGPoint(x: w-1.3, y: 0))
            context.saveGState()
            context.addPath(rim); context.setLineWidth(2.5); context.replacePathWithStrokedPath(); context.clip()
            let lightAlpha = min(0.5, 0.20*rimStrength)
            NSGradient(colors: [.clear, NSColor(white: 1, alpha: lightAlpha), NSColor(white: 1, alpha: lightAlpha*0.35)])?
                .draw(in: NSRect(x: 0, y: max(0, h-9), width: w, height: 9), angle: 90)
            context.restoreGState()
        }

    }
    deinit { timer?.invalidate() }
}
