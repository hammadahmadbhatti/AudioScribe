import SwiftUI

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

extension Color {
    static var groupedBackground: Color {
        #if os(iOS)
        return Color(.systemGroupedBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var secondaryBackground: Color {
        #if os(iOS)
        return Color(.secondarySystemBackground)
        #else
        return Color(nsColor: .underPageBackgroundColor)
        #endif
    }
}
