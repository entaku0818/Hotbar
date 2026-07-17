import SwiftUI
import AppKit

/// Shown when the 14-day trial has expired and no license is active.
struct LicenseGateView: View {
    @ObservedObject var licenseManager: LicenseManager
    @State private var licenseKeyInput = ""
    @State private var isActivating = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Your free trial has ended")
                .font(.title2)
                .fontWeight(.bold)

            Text("Hotbar is ¥1,500, one-time purchase — no subscription. " +
                 "Purchases are refundable within 14 days.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Buy on Polar") {
                NSWorkspace.shared.open(PolarConfig.checkoutURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()
                .padding(.vertical, 4)

            VStack(spacing: 8) {
                Text("Already purchased? Enter your license key:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("License key", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)

                    Button(isActivating ? "Checking…" : "Activate") {
                        activate()
                    }
                    .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                }
                .frame(maxWidth: 360)

                if let error = licenseManager.activationErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
        }
        .padding(32)
        .frame(width: 420)
    }

    private func activate() {
        isActivating = true
        Task {
            await licenseManager.activate(licenseKey: licenseKeyInput)
            isActivating = false
        }
    }
}
