import SwiftUI
import AppKit

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "square.grid.3x3.fill",
            title: "Welcome to Hotbar",
            description: "A developer window switcher inspired by FF14's hotbar. Switch between windows instantly with keyboard shortcuts.",
            action: nil
        ),
        OnboardingStep(
            icon: "accessibility",
            title: "Grant Accessibility Access",
            description: "Hotbar needs Accessibility permission to read window information and bring apps to the foreground.",
            action: "Open System Settings"
        ),
        OnboardingStep(
            icon: "keyboard",
            title: "Open with ⌥+Space",
            description: "Press ⌥+Space (Option+Space) at any time to open the Hotbar overlay, even while using other apps.",
            action: nil
        ),
        OnboardingStep(
            icon: "square.grid.2x2",
            title: "Browse Your Windows",
            description: "All open windows appear as thumbnails in the grid. Click or use arrow keys to switch to it instantly.",
            action: nil
        ),
        OnboardingStep(
            icon: "1.square.fill",
            title: "Use the Hotbar",
            description: "Hold a number key (1–9) to register a window to that slot. Press ⌘+1–9 to jump directly to it later.",
            action: nil
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { idx in
                    Circle()
                        .fill(idx <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.spring(), value: currentStep)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
            let step = steps[currentStep]
            VStack(spacing: 20) {
                Image(systemName: step.icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .id(currentStep)

                Text(step.title)
                    .font(.title)
                    .fontWeight(.bold)

                Text(step.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                if currentStep == 1 {
                    AccessibilityStatusView(isGranted: $accessibilityGranted)
                }

                if let actionTitle = step.action {
                    Button(actionTitle) {
                        handleStepAction()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 48)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.4), value: currentStep)
            .id(currentStep)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentStep == steps.count - 1 {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && !accessibilityGranted)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 600, height: 450)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if currentStep == 1 {
                accessibilityGranted = AXIsProcessTrusted()
            }
        }
    }

    private func handleStepAction() {
        if currentStep == 1,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AccessibilityStatusView: View {
    @Binding var isGranted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .red)
            Text(isGranted ? "Accessibility access granted" : "Accessibility access not granted")
                .font(.callout)
                .foregroundStyle(isGranted ? .green : .red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let action: String?
}
