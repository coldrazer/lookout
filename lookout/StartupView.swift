import SwiftUI

/// Branded launch screen shown before the main app. Calls `onEnter` when the user taps Enter.
struct StartupView: View {
    var onEnter: () -> Void

    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

                emblem
                    .padding(.bottom, 36)

                VStack(spacing: 10) {
                    Text("Lookout")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .tracking(-1)

                    Text("BY VEXO")
                        .font(.footnote.weight(.semibold))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                Text("A gentle guardian for every call.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)

                Spacer()

                enterButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.15)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Pieces

    /// Deep gradient with soft, slowly drifting color glows.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.15),
                    Color(red: 0.08, green: 0.06, blue: 0.25),
                    Color(red: 0.02, green: 0.10, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.35, green: 0.40, blue: 1.0).opacity(0.45))
                .frame(width: 360)
                .blur(radius: 90)
                .offset(x: pulse ? -110 : -60, y: pulse ? -260 : -200)

            Circle()
                .fill(Color(red: 0.10, green: 0.85, blue: 0.80).opacity(0.35))
                .frame(width: 320)
                .blur(radius: 100)
                .offset(x: pulse ? 120 : 80, y: pulse ? 260 : 320)
        }
        .ignoresSafeArea()
    }

    /// Glowing shield icon with concentric rings.
    private var emblem: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(.white.opacity(0.08 - Double(i) * 0.02), lineWidth: 1)
                    .frame(width: 150 + CGFloat(i) * 50)
                    .scaleEffect(pulse ? 1.05 : 0.95)
            }

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 130)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color(red: 0.4, green: 0.5, blue: 1.0).opacity(0.5), radius: 30)

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.65, blue: 1.0), Color(red: 0.3, green: 0.95, blue: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating)
        }
        .environment(\.colorScheme, .dark)
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var enterButton: some View {
        Button(action: onEnter) {
            HStack(spacing: 10) {
                Text("Enter")
                    .font(.title3.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.40, green: 0.45, blue: 1.0), Color(red: 0.20, green: 0.75, blue: 0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.5), radius: 20, y: 8)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Subtle scale-down feedback while the button is pressed.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    StartupView(onEnter: {})
}
