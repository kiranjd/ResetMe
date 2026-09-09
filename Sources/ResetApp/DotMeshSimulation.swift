import Foundation
import CoreGraphics

/// A spring mesh attached to the surface until a measured shake releases its bonds.
/// Released particles use the supplied gravity vector and spatially hashed contacts.
final class DotMeshSimulation {
    struct Particle {
        var position: CGPoint
        var velocity = CGPoint.zero
        let home: CGPoint
    }
    struct Link {
        let a: Int, b: Int
        let rest: Double
        let delay: Double
        var active = true
    }
    private(set) var particles: [Particle] = []
    private(set) var links: [Link] = []
    private(set) var broken = false
    private var fractureTime = 0.0
    private var age = 0.0
    private(set) var size = CGSize.zero
    private var spacing = 0.0
    private var compression = 0.0
    func configure(size: CGSize, spacing: Double, compression: Double) {
        guard self.size != size || self.spacing != spacing || self.compression != compression else { return }
        self.size = size; self.spacing = spacing; self.compression = compression
        rebuild()
    }
    func rebuild() {
        particles.removeAll(keepingCapacity: true); links.removeAll(keepingCapacity: true)
        broken = false; fractureTime = 0; age = 0
        guard size.width > 1, size.height > 1, spacing > 0 else { return }
        let columns = max(1, Int(size.width/spacing)), rows = max(1, Int(size.height/spacing))
        for row in 0..<rows { for column in 0..<columns {
            var x = Double(column)*spacing+2, y = Double(row)*spacing+2
            let edge = max(1, compression)
            func curve(_ d: Double) -> Double { edge*(1-cos(max(0,d)/edge * .pi/2)) }
            if x < edge { x = curve(x) }
            else if x > size.width-edge { x = size.width-curve(size.width-x) }
            if y > size.height-edge { y = size.height-curve(size.height-y) }
            let cornerY = max(0,y-(size.height-18))
            let inset = 18-sqrt(max(0,324-cornerY*cornerY))
            x = inset+(size.width-2*inset)*x/max(1,size.width)
            particles.append(Particle(position: CGPoint(x: x,y: y), home: CGPoint(x: x,y: y)))
        }}
        for row in 0..<rows { for column in 0..<columns {
            let a = row*columns+column
            if column+1 < columns { addLink(a,a+1) }
            if row+1 < rows { addLink(a,a+columns) }
        }}
    }
    private func addLink(_ a: Int,_ b: Int) {
        let p = particles[a].home, q = particles[b].home
        links.append(Link(a: a,b: b,rest: hypot(q.x-p.x,q.y-p.y),delay: Double((a*31+b*17)%101)/100*0.28))
    }
    func breakApart() { guard !broken else { return }; broken = true; fractureTime = 0 }
    @discardableResult func step(dt: Double, gravity: CGPoint, shake: CGPoint, shock: Double, threshold: Double, stiffness: Double, gravityScale: Double, restitution: Double, diameter: Double) -> Bool {
        guard !particles.isEmpty else { return false }
        age += dt
        if age > 0.5 && shock >= threshold { breakApart() }
        let count = max(1, Int(ceil(dt/(1.0/120))))
        let step = min(0.05,dt)/Double(count)
        var changed = false
        for _ in 0..<count {
            if broken { fractureTime += step }
            let release = broken ? min(1,fractureTime/0.28) : 0
            for i in particles.indices {
                let previous = particles[i].position
                let variation = 0.85+Double(i%17)/16*0.3
                let homeX = (particles[i].home.x-previous.x)*stiffness*(1-release)
                let homeY = (particles[i].home.y-previous.y)*stiffness*(1-release)
                let gravityWeight = broken ? release : 0.035
                let ax = homeX+gravity.x*gravityScale*gravityWeight-shake.x*350*variation
                let ay = homeY+gravity.y*gravityScale*gravityWeight-shake.y*350*variation
                let drag = exp(-(broken ? 0.35 : 10)*step)
                particles[i].velocity.x = max(-500,min(500,(particles[i].velocity.x+ax*step)*drag))
                particles[i].velocity.y = max(-500,min(500,(particles[i].velocity.y+ay*step)*drag))
            }
            for index in links.indices where links[index].active {
                if broken && fractureTime >= links[index].delay { links[index].active = false; continue }
                let link = links[index], p = particles[link.a].position, q = particles[link.b].position
                let dx = q.x-p.x, dy = q.y-p.y, length = max(0.001,hypot(dx,dy))
                let force = (length-link.rest)*stiffness*0.7*step
                particles[link.a].velocity.x += dx/length*force; particles[link.a].velocity.y += dy/length*force
                particles[link.b].velocity.x -= dx/length*force; particles[link.b].velocity.y -= dy/length*force
            }
            for i in particles.indices {
                particles[i].position.x += particles[i].velocity.x*step
                particles[i].position.y += particles[i].velocity.y*step
                if abs(particles[i].velocity.x)+abs(particles[i].velocity.y)>0.05 { changed = true }
            }
            if broken {
                contacts(diameter: diameter)
                let radius = max(0.25,diameter/2)
                for i in particles.indices {
                    let p = particles[i].position
                    if p.x < radius { particles[i].position.x = radius; particles[i].velocity.x = abs(particles[i].velocity.x)*restitution }
                    if p.x > size.width-radius { particles[i].position.x = size.width-radius; particles[i].velocity.x = -abs(particles[i].velocity.x)*restitution }
                    if p.y < radius { particles[i].position.y = radius; particles[i].velocity.y = abs(particles[i].velocity.y)*restitution }
                    if p.y > size.height-radius {
                        particles[i].position.y = size.height-radius
                        particles[i].velocity.y = abs(particles[i].velocity.y)<8 ? 0 : -abs(particles[i].velocity.y)*restitution
                        particles[i].velocity.x *= 0.94
                    }
                }
            }
        }
        return changed || (broken && fractureTime<0.35)
    }
    private func contacts(diameter: Double) {
        let cell = max(1,diameter), columns = Int(ceil(size.width/cell))+4
        var grid: [Int:[Int]] = [:]
        for i in particles.indices {
            let p = particles[i].position
            let x = Int(floor(p.x/cell)), y = Int(floor(p.y/cell))
            for cy in (y-1)...(y+1) { for cx in (x-1)...(x+1) {
                guard let others = grid[cy*columns+cx] else { continue }
                for j in others {
                    var dx = particles[i].position.x-particles[j].position.x
                    var dy = particles[i].position.y-particles[j].position.y
                    let square = dx*dx+dy*dy
                    guard square < diameter*diameter else { continue }
                    if square < 0.0001 { dx = 0.01; dy = 0.01 }
                    let distance = hypot(dx,dy), nx = dx/distance, ny = dy/distance
                    let correction = (diameter-distance)*0.5
                    particles[i].position.x += nx*correction; particles[i].position.y += ny*correction
                    particles[j].position.x -= nx*correction; particles[j].position.y -= ny*correction
                    let relative = (particles[i].velocity.x-particles[j].velocity.x)*nx+(particles[i].velocity.y-particles[j].velocity.y)*ny
                    if relative < 0 {
                        let impulse = -relative*0.55
                        particles[i].velocity.x += nx*impulse; particles[i].velocity.y += ny*impulse
                        particles[j].velocity.x -= nx*impulse; particles[j].velocity.y -= ny*impulse
                    }
                }
            }}
            grid[y*columns+x,default: []].append(i)
        }
    }
}
