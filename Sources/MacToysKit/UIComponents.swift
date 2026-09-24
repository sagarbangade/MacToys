import SwiftUI

// MARK: - Modern Siri / Apple Intelligence Chromatic Gradients

public struct SiriGlow {
    public static let chromaticGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.22, blue: 0.48), // Electric Magenta
            Color(red: 0.65, green: 0.32, blue: 0.98), // Siri Violet
            Color(red: 0.18, green: 0.65, blue: 0.98), // Celestial Cyan
            Color(red: 0.98, green: 0.62, blue: 0.22)  // Liquid Amber
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let angularGlow = AngularGradient(
        colors: [
            Color(red: 0.98, green: 0.22, blue: 0.48),
            Color(red: 0.65, green: 0.32, blue: 0.98),
            Color(red: 0.18, green: 0.65, blue: 0.98),
            Color(red: 0.98, green: 0.62, blue: 0.22),
            Color(red: 0.98, green: 0.22, blue: 0.48)
        ],
        center: .center
    )
}

// MARK: - macOS 27 Liquid Glass Card

public struct PremiumCard<Content: View>: View {
    public let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(
            // Top specular rim glint
            VStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                Spacer()
            }
        )
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
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(iconColor.opacity(0.3), lineWidth: 0.5)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .frame(width: 34, height: 34)
            .shadow(color: iconColor.opacity(0.25), radius: 4, x: 0, y: 1.5)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
            .opacity(0.4)
            .padding(.leading, 66)
    }
}

// MARK: - Animated Siri-Inspired Mesh Gradient

public struct MeshGradientBackground: View {
    @State private var animate = false
    public var color1: Color
    public var color2: Color
    
    public init(color1: Color = Color(red: 0.65, green: 0.32, blue: 0.98), color2: Color = Color(red: 0.18, green: 0.65, blue: 0.98)) {
        self.color1 = color1
        self.color2 = color2
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.14),
                    Color(red: 0.12, green: 0.11, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Luminous iridescent orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.98, green: 0.22, blue: 0.48).opacity(0.55), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 320, height: 320)
                .offset(x: animate ? -80 : 80, y: animate ? -30 : 30)
                .blur(radius: 50)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.45, green: 0.35, blue: 0.98).opacity(0.65), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: animate ? 100 : -60, y: animate ? 40 : -40)
                .blur(radius: 55)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.15, green: 0.75, blue: 0.98).opacity(0.5), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 280, height: 280)
                .offset(x: animate ? -40 : 120, y: animate ? 60 : -20)
                .blur(radius: 45)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
        .clipped()
    }
}

// MARK: - Reusable Appearance Theme Selector

public struct AppearancePickerView: View {
    @Binding public var currentTheme: AppTheme
    
    public init(currentTheme: Binding<AppTheme>) {
        self._currentTheme = currentTheme
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentTheme = theme
                    }
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: theme.icon)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(currentTheme == theme ? .white : .primary.opacity(0.8))
                            Spacer()
                            if currentTheme == theme {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                        
                        Text(theme.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(currentTheme == theme ? .white : .primary)
                        
                        Text(theme.subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(currentTheme == theme ? .white.opacity(0.85) : .secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(height: 105)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                currentTheme == theme
                                ? AnyShapeStyle(SiriGlow.chromaticGradient)
                                : AnyShapeStyle(.ultraThinMaterial)
                            )
                            .shadow(color: currentTheme == theme ? Color(red: 0.65, green: 0.32, blue: 0.98).opacity(0.35) : Color.black.opacity(0.08), radius: 8, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                currentTheme == theme
                                ? Color.white.opacity(0.6)
                                : Color.white.opacity(0.15),
                                lineWidth: currentTheme == theme ? 1.5 : 0.8
                            )
                    )
                    .scaleEffect(currentTheme == theme ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
