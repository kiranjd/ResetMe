import SwiftUI

private struct ContentShade: ViewModifier {
    let spread: CGFloat
    @ObservedObject private var scene = SceneSettings.shared
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(scene["contentShade"]))
                .padding(-(spread + 7)).blur(radius: spread + 3).allowsHitTesting(false)
        }
    }
}
extension View {
    func matteContentShade(spread: CGFloat = 5) -> some View { modifier(ContentShade(spread: spread)) }
}
