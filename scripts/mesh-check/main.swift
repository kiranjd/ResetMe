import Foundation
import CoreGraphics
let mesh = DotMeshSimulation()
mesh.configure(size: CGSize(width: 120,height: 160),spacing: 6,compression: 12)
func advance(_ gravity: CGPoint = CGPoint(x: 0,y: 1), shock: Double = 0) {
    mesh.step(dt: 1.0/60,gravity: gravity,shake: .zero,shock: shock,threshold: 0.45,stiffness: 90,gravityScale: 550,restitution: 0.35,diameter: 3.5)
}
for _ in 0..<60 { advance(shock: 0.1) }
precondition(!mesh.broken && mesh.links.allSatisfy(\.active), "Gentle input broke the mesh")
advance(shock: 0.8)
precondition(mesh.broken, "Shake failed to break mesh")
for _ in 0..<100 { advance() }
precondition(mesh.links.allSatisfy { !$0.active })
let meanY = mesh.particles.map(\.position.y).reduce(0,+)/Double(mesh.particles.count)
precondition(meanY > 100, "Loose particles did not fall")
let oldX = mesh.particles.map(\.position.x).reduce(0,+)/Double(mesh.particles.count)
for _ in 0..<120 { advance(CGPoint(x: 1,y: 0)) }
let newX = mesh.particles.map(\.position.x).reduce(0,+)/Double(mesh.particles.count)
precondition(newX > oldX+5, "Changed gravity did not move particles sideways")
precondition(mesh.particles.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.x >= 1.7 && $0.position.x <= 118.3 && $0.position.y >= 1.7 && $0.position.y <= 158.3 })
mesh.rebuild()
precondition(!mesh.broken && mesh.particles.allSatisfy { $0.position == $0.home })
let large = DotMeshSimulation()
large.configure(size: CGSize(width: 348,height: 300),spacing: 6,compression: 24)
large.breakApart()
let begin = ProcessInfo.processInfo.systemUptime
for _ in 0..<30 { large.step(dt: 1.0/30,gravity: CGPoint(x: 0,y: 1),shake: .zero,shock: 0,threshold: 0.45,stiffness: 90,gravityScale: 550,restitution: 0.35,diameter: 3.5) }
let ms = (ProcessInfo.processInfo.systemUptime-begin)*1000/30
print(String(format:"PASS: gentle flex, shake fracture, gravity rotation, bounds, rebuild; %d particles %.1f ms/frame physics",large.particles.count,ms))
