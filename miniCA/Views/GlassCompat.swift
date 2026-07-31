import SwiftUI

// Liquid-Glass polish on macOS 26 (Tahoe), graceful fallback on macOS 15.

extension View {
    /// Prominent call-to-action button: glass on Tahoe, borderedProminent before.
    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Capsule badge background: glass on Tahoe, thin material before.
    @ViewBuilder
    func badgeBackground(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint.opacity(0.4)), in: .capsule)
        } else {
            background(tint.opacity(0.2), in: .capsule)
        }
    }
}
