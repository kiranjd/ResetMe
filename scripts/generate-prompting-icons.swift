import Foundation
import SwiftUI

@main struct GeneratePromptingIcons {
    static func path(_ path: Path) -> String {
        var commands: [String] = []
        func point(_ p: CGPoint) -> String { String(format: "%.3f %.3f", Double(p.x), Double(p.y)) }
        path.cgPath.applyWithBlock { pointer in
            let e = pointer.pointee
            switch e.type {
            case .moveToPoint: commands.append("M" + point(e.points[0]))
            case .addLineToPoint: commands.append("L" + point(e.points[0]))
            case .addQuadCurveToPoint: commands.append("Q" + point(e.points[0]) + " " + point(e.points[1]))
            case .addCurveToPoint: commands.append("C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined(separator: " ")
    }
    static func main() throws {
        let output = URL(fileURLWithPath: "Assets/Brand/Prompting", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for symbol in PromptingSymbol.allCases {
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
              <title>ResetMe \(symbol.rawValue)</title>
              <path d="\(path(symbol.outline))" stroke="#fefae0" stroke-opacity=".78" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"/>
              <path d="\(path(symbol.accent))" fill="#606c38" stroke="#fefae0" stroke-opacity=".3" stroke-width=".5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            """
            try (svg + "\n").write(to: output.appendingPathComponent(symbol.rawValue + ".svg"), atomically: true, encoding: .utf8)
        }
    }
}
