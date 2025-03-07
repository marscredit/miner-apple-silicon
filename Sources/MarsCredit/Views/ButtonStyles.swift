import SwiftUI

struct MiningButtonStyle: ButtonStyle {
    let isDestructive: Bool
    
    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gunship(size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDestructive ? Color.red : Color(red: 1, green: 0, blue: 0))
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
    }
}

extension View {
    func miningButtonStyle(isDestructive: Bool = false) -> some View {
        buttonStyle(MiningButtonStyle(isDestructive: isDestructive))
    }
} 