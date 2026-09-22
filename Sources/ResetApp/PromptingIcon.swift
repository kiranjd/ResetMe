import SwiftUI

/// A single set of vector paths drives the native glyphs and exported SVG assets.
/// Rounded cream outlines and restrained olive details carry the brand without leaf motifs.
enum PromptingSymbol: String, CaseIterable {
    case time, switches, tasks, prompts, focus, parallel

    var outline: Path {
        var p = Path()
        switch self {
        case .time:
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
            p.move(to: CGPoint(x: 12, y: 7.5)); p.addLine(to: CGPoint(x: 12, y: 12)); p.addLine(to: CGPoint(x: 15.5, y: 14))
        case .switches:
            p.move(to: CGPoint(x: 4, y: 8)); p.addCurve(to: CGPoint(x: 19, y: 8), control1: CGPoint(x: 8, y: 3), control2: CGPoint(x: 15, y: 3))
            p.move(to: CGPoint(x: 19, y: 4.5)); p.addLine(to: CGPoint(x: 19, y: 8)); p.addLine(to: CGPoint(x: 15.5, y: 8))
            p.move(to: CGPoint(x: 20, y: 16)); p.addCurve(to: CGPoint(x: 5, y: 16), control1: CGPoint(x: 16, y: 21), control2: CGPoint(x: 9, y: 21))
            p.move(to: CGPoint(x: 5, y: 19.5)); p.addLine(to: CGPoint(x: 5, y: 16)); p.addLine(to: CGPoint(x: 8.5, y: 16))
        case .tasks:
            p.addRoundedRect(in: CGRect(x: 3.5, y: 10.5, width: 7, height: 9), cornerSize: CGSize(width: 2, height: 2))
            p.addRoundedRect(in: CGRect(x: 13.5, y: 10.5, width: 7, height: 9), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 7, y: 7)); p.addLine(to: CGPoint(x: 7, y: 5.5)); p.addQuadCurve(to: CGPoint(x: 9, y: 3.5), control: CGPoint(x: 7, y: 3.5)); p.addLine(to: CGPoint(x: 14.5, y: 3.5))
        case .prompts:
            p.move(to: CGPoint(x: 17.5, y: 4.5)); p.addLine(to: CGPoint(x: 6.5, y: 4.5)); p.addQuadCurve(to: CGPoint(x: 3.5, y: 7.5), control: CGPoint(x: 3.5, y: 4.5)); p.addLine(to: CGPoint(x: 3.5, y: 14)); p.addQuadCurve(to: CGPoint(x: 6.5, y: 17), control: CGPoint(x: 3.5, y: 17)); p.addLine(to: CGPoint(x: 7.5, y: 17)); p.addLine(to: CGPoint(x: 7.5, y: 20)); p.addLine(to: CGPoint(x: 12, y: 17)); p.addLine(to: CGPoint(x: 17.5, y: 17)); p.addQuadCurve(to: CGPoint(x: 20.5, y: 14), control: CGPoint(x: 20.5, y: 17)); p.addLine(to: CGPoint(x: 20.5, y: 7.5)); p.addQuadCurve(to: CGPoint(x: 17.5, y: 4.5), control: CGPoint(x: 20.5, y: 4.5)); p.closeSubpath()
            p.move(to: CGPoint(x: 7.5, y: 9)); p.addLine(to: CGPoint(x: 12, y: 9))
            p.move(to: CGPoint(x: 7.5, y: 12.5)); p.addLine(to: CGPoint(x: 15, y: 12.5))
        case .focus:
            p.move(to: CGPoint(x: 8, y: 3.5)); p.addLine(to: CGPoint(x: 5.5, y: 3.5)); p.addQuadCurve(to: CGPoint(x: 3.5, y: 5.5), control: CGPoint(x: 3.5, y: 3.5)); p.addLine(to: CGPoint(x: 3.5, y: 8))
            p.move(to: CGPoint(x: 16, y: 3.5)); p.addLine(to: CGPoint(x: 18.5, y: 3.5)); p.addQuadCurve(to: CGPoint(x: 20.5, y: 5.5), control: CGPoint(x: 20.5, y: 3.5)); p.addLine(to: CGPoint(x: 20.5, y: 8))
            p.move(to: CGPoint(x: 3.5, y: 16)); p.addLine(to: CGPoint(x: 3.5, y: 18.5)); p.addQuadCurve(to: CGPoint(x: 5.5, y: 20.5), control: CGPoint(x: 3.5, y: 20.5)); p.addLine(to: CGPoint(x: 8, y: 20.5))
            p.move(to: CGPoint(x: 16, y: 20.5)); p.addLine(to: CGPoint(x: 18.5, y: 20.5)); p.addQuadCurve(to: CGPoint(x: 20.5, y: 18.5), control: CGPoint(x: 20.5, y: 20.5)); p.addLine(to: CGPoint(x: 20.5, y: 16))
        case .parallel:
            p.addRoundedRect(in: CGRect(x: 3.5, y: 4, width: 6, height: 16), cornerSize: CGSize(width: 3, height: 3))
            p.addRoundedRect(in: CGRect(x: 14.5, y: 4, width: 6, height: 16), cornerSize: CGSize(width: 3, height: 3))
            p.move(to: CGPoint(x: 6.5, y: 8)); p.addLine(to: CGPoint(x: 6.5, y: 12))
            p.move(to: CGPoint(x: 17.5, y: 8)); p.addLine(to: CGPoint(x: 17.5, y: 12))
        }
        return p
    }
    var accent: Path {
        var p = Path()
        switch self {
        case .time:
            p.addRoundedRect(in: CGRect(x: 11.2, y: 7, width: 1.6, height: 5.5), cornerSize: CGSize(width: 0.8, height: 0.8))
        case .focus:
            p.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
        case .parallel:
            p.addRoundedRect(in: CGRect(x: 5.3, y: 14, width: 2.4, height: 3), cornerSize: CGSize(width: 1.2, height: 1.2))
            p.addRoundedRect(in: CGRect(x: 16.3, y: 14, width: 2.4, height: 3), cornerSize: CGSize(width: 1.2, height: 1.2))
        case .prompts:
            p.addRoundedRect(in: CGRect(x: 7, y: 12, width: 8.5, height: 1.4), cornerSize: CGSize(width: 0.7, height: 0.7))
        case .switches, .tasks: break
        }
        return p
    }

}

struct PromptingIcon: View {
    let symbol: PromptingSymbol
    var size: CGFloat = 32
    var body: some View {
        Canvas { context, dimensions in
            context.scaleBy(x: dimensions.width / 24, y: dimensions.height / 24)
            context.stroke(symbol.outline, with: .color(BrandPalette.cream.opacity(0.78)), style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))
            context.fill(symbol.accent, with: .color(BrandPalette.olive))
            context.stroke(symbol.accent, with: .color(BrandPalette.cream.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, lineCap: .round, lineJoin: .round))
        }.frame(width: size, height: size).accessibilityHidden(true).allowsHitTesting(false)
    }
}
