import SwiftUI

public struct PremiumCard<Content: View>: View {
    public let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

public struct PremiumRow: View {
    public let icon: String
    public let iconColor: Color
    public let title: String
    public let subtitle: String?
    public let content: AnyView
    
    public init<V: View>(icon: String, iconColor: Color = .accentColor, title: String, subtitle: String? = nil, @ViewBuilder content: () -> V) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.content = AnyView(content())
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

public struct PremiumDivider: View {
    public init() {}
    public var body: some View {
        Divider()
            .padding(.leading, 64) // Align with text
    }
}

public struct MeshGradientBackground: View {
    @State private var animate = false
    public var color1: Color
    public var color2: Color
    
    public init(color1: Color, color2: Color) {
        self.color1 = color1
        self.color2 = color2
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(colors: [color1.opacity(0.3), color2.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            Circle()
                .fill(color1.opacity(0.4))
                .frame(width: 300)
                .blur(radius: 60)
                .offset(x: animate ? -100 : 100, y: animate ? -50 : 50)
            
            Circle()
                .fill(color2.opacity(0.4))
                .frame(width: 300)
                .blur(radius: 60)
                .offset(x: animate ? 100 : -100, y: animate ? 50 : -50)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
        .clipped()
    }
}
