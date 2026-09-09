import AppKit

/// One optical environment shared by every curved surface in the notch.
/// Artistic light intensity; dielectric angular response uses Schlick Fresnel.
struct SceneLight {
    let strength: Double, broad: Double, width: Double, rim: Double, top: Double, f0: Double
    init(_ s: SceneSettings) {
        f0 = pow((s["ior"]-1)/(s["ior"]+1),2)
        strength = s["lightStrength"]; broad = s["softbox"]; width = s["softWidth"]
        rim = s["rimLight"]; top = s["topLight"]
    }
}
enum GlassSceneOptics {
    static func fresnel(_ nz: Double, f0: Double = 0.04) -> Double { f0 + (1-f0) * pow(1-nz, 5) }
    static func reflection(nx: Double, ny: Double, nz: Double, point: NSPoint, light: NSPoint, lighting: SceneLight) -> Double {
        let shift = 0.75*tanh((light.x-point.x) / 220)
        let tilt = 0.6*tanh((light.y-point.y) / 240)
        let rx = 2*nx*nz, ry = 2*ny*nz
        let softbox = exp(-pow((rx+0.62-shift+ry*0.15)/lighting.width,2))
            * (0.78+0.22*exp(-pow((ry+0.3-tilt)/0.8,2)))
        let strip = exp(-pow((rx-0.79-shift*0.4)/0.065,2))*0.65
        let top = exp(-pow((ry+0.72-tilt)/0.16,2))*0.8
        return (softbox*lighting.broad+strip*lighting.rim+top*lighting.top)*(fresnel(nz, f0: lighting.f0)+0.045)*lighting.strength
    }

    /// A tall reflected light in the pane's front-facing directions. The reflected ray,
    /// rather than view-space stripes, makes it bend continuously around the bevel.
    static func paneReflection(nx: Double, ny: Double, nz: Double, point: NSPoint, light: NSPoint, lighting: SceneLight, width: Double) -> Double {
        // A compact overhead lamp, reflected as a localized elliptical glint.
        let dx = (light.x-point.x)/240
        let dy = (light.y-point.y)/300
        let length = sqrt(dx*dx+dy*dy+1)
        let lx = dx/length, ly = dy/length, lz = 1/length
        let halfLength = sqrt(lx*lx+ly*ly+(lz+1)*(lz+1))
        let hx = lx/halfLength, hy = ly/halfLength
        let lampWidth = max(0.035, width*0.45)
        let lamp = exp(-pow((nx-hx)/lampWidth,2)-pow((ny-hy)/(lampWidth*0.65),2))
        return lamp*1.8*(fresnel(nz, f0: lighting.f0)+0.035)*lighting.strength
    }

    /// Small sphere rendered with exactly the same reflected environment as the bars.
    static func dotImage(point: NSPoint, light: NSPoint) -> NSImage? {
        let settings = SceneSettings.shared
        let lighting = SceneLight(settings)
        let flat = settings["dotFlat"], curve = settings["dotCurve"]
        let reflectivity = settings["dotReflection"], brightness = settings["dotBody"]
        let tint = settings.rgb("dot"), lightColor = settings.rgb("light")
        let side = 12
        var bytes = [UInt8](repeating: 0, count: side*side*4)
        for y in 0..<side { for x in 0..<side {
            let nx = (Double(x)+0.5)/Double(side)*2-1
            let ny = (Double(y)+0.5)/Double(side)*2-1
            let radius = nx*nx+ny*ny
            guard radius < 1 else { continue }
            let edge = max(0, (sqrt(radius)-flat)/(1-flat))
            let bend = edge*curve
            let nz = sqrt(1-radius*bend*bend)
            let shine = reflection(nx: nx*bend, ny: ny*bend, nz: nz, point: point, light: light, lighting: lighting)
            let body = 0.035 + 0.015*nz + pow(1-nz,3)*0.035
            let i = (y*side+x)*4
            for channel in 0..<3 {
                // Dielectric reflections keep the light's color; tint belongs to the body.
                let diffuse = body*brightness*pow(tint[channel],2.2)
                let specular = shine*reflectivity*lightColor[channel]
                let value = pow(min(1,diffuse+specular),1/2.2)
                bytes[i+channel] = UInt8(value*255)
            }
            bytes[i+3] = UInt8(min(1,(1-sqrt(radius))*Double(side))*255)
        }}
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 2.2, height: 2.2))
    }
}
