import Foundation

enum LicenseStatus: Equatable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed
    /// A license key is stored, but it has not been successfully re-validated
    /// against Polar within the offline grace period. Gated like an expired
    /// trial, but told apart so the gate can explain itself to a paying user.
    case licenseValidationExpired
}

extension Notification.Name {
    /// Posted when a gated feature (e.g. the overlay) is requested but the
    /// trial has expired and no license is active.
    static let licenseGateRequested = Notification.Name("licenseGateRequested")
}

/// Tracks the 14-day free trial and Polar.sh license activation state.
///
/// A stored license key alone does **not** unlock the app. `.licensed`
/// requires all three of: the key, the activation instance id, and a
/// successful server validation within `offlineGracePeriod`. Re-validation
/// runs at launch (`revalidate()`); if the network is unreachable the last
/// successful validation carries the user for 14 more days, after which the
/// gate returns. A definitive "not valid" answer from Polar (refund, revoke)
/// clears the license immediately.
///
/// State lives in UserDefaults for v1 (simple, and injectable for tests).
/// UserDefaults is user-writable, so this is a speed bump rather than a
/// tamper-proof scheme — but it can no longer be lifted by writing a single
/// arbitrary string, and it expires without server contact.
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60

    /// How long a successful validation keeps the app unlocked without any
    /// further server contact.
    static let offlineGracePeriod: TimeInterval = 14 * 24 * 60 * 60

    @Published private(set) var status: LicenseStatus
    @Published var activationErrorMessage: String?

    private let defaults: UserDefaults
    private let client: LicenseClient
    private let now: () -> Date

    private enum Keys {
        static let trialStartDate = "licenseTrialStartDate"
        static let licenseKey = "licenseKey"
        static let instanceID = "licenseInstanceID"
        static let lastValidatedAt = "licenseLastValidatedAt"
    }

    init(
        defaults: UserDefaults = .standard,
        client: LicenseClient = PolarLicenseClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.client = client
        self.now = now

        if defaults.object(forKey: Keys.trialStartDate) == nil {
            defaults.set(now(), forKey: Keys.trialStartDate)
        }
        self.status = Self.computeStatus(defaults: defaults, now: now())
    }

    var isLicensed: Bool {
        if case .licensed = status { return true }
        return false
    }

    /// True when a gated feature should be blocked.
    var isGated: Bool {
        status == .trialExpired || status == .licenseValidationExpired
    }

    func refreshStatus() {
        status = Self.computeStatus(defaults: defaults, now: now())
    }

    @MainActor
    func activate(licenseKey: String, instanceName: String = ProcessInfo.processInfo.hostName) async {
        activationErrorMessage = nil
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            activationErrorMessage = "Please enter a license key."
            return
        }

        do {
            let response = try await client.activate(licenseKey: trimmedKey, instanceName: instanceName)
            guard response.activated, let instance = response.instance else {
                activationErrorMessage = response.error ?? "This license key could not be activated."
                return
            }
            defaults.set(trimmedKey, forKey: Keys.licenseKey)
            defaults.set(instance.id, forKey: Keys.instanceID)
            // Activation is itself a successful server check — start the clock.
            defaults.set(now(), forKey: Keys.lastValidatedAt)
            refreshStatus()
        } catch {
            activationErrorMessage = error.localizedDescription
        }
    }

    /// Re-checks the stored key against Polar. Call at launch.
    ///
    /// - success            → the grace period restarts from now
    /// - "not valid"        → the license is cleared (refunded/revoked keys lock out)
    /// - network failure    → nothing changes; the remaining grace period still applies
    @MainActor
    func revalidate() async {
        guard let key = defaults.string(forKey: Keys.licenseKey), !key.isEmpty,
              let instanceID = defaults.string(forKey: Keys.instanceID), !instanceID.isEmpty else {
            refreshStatus()
            return
        }

        do {
            let response = try await client.validate(licenseKey: key, instanceID: instanceID)
            if response.valid {
                defaults.set(now(), forKey: Keys.lastValidatedAt)
            } else {
                clearLicense()
            }
        } catch {
            // Offline or server unreachable: fall back to the grace period.
            // Deliberately does not extend it.
        }
        refreshStatus()
    }

    /// Clears the stored license, reverting to trial/expired state. Exposed
    /// for debugging and tests — not wired to any menu item in v1.
    func deactivate() {
        clearLicense()
        refreshStatus()
    }

    private func clearLicense() {
        defaults.removeObject(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.instanceID)
        defaults.removeObject(forKey: Keys.lastValidatedAt)
    }

    private static func computeStatus(defaults: UserDefaults, now: Date) -> LicenseStatus {
        if let key = defaults.string(forKey: Keys.licenseKey), !key.isEmpty {
            // A key on its own proves nothing — it also needs the activation
            // id handed back by Polar and a recent successful validation.
            let instanceID = defaults.string(forKey: Keys.instanceID)
            let lastValidated = defaults.object(forKey: Keys.lastValidatedAt) as? Date

            if let instanceID, !instanceID.isEmpty, let lastValidated {
                let elapsed = now.timeIntervalSince(lastValidated)
                // A negative elapsed time means the clock moved backwards (or
                // the stamp was forged into the future); treat it as stale
                // rather than as an unlimited grace period.
                if elapsed >= 0 && elapsed < offlineGracePeriod {
                    return .licensed
                }
            }
            return .licenseValidationExpired
        }

        guard let start = defaults.object(forKey: Keys.trialStartDate) as? Date else {
            return .trial(daysRemaining: Int(trialDuration / 86400))
        }
        let remaining = trialDuration - now.timeIntervalSince(start)
        guard remaining > 0 else {
            return .trialExpired
        }
        return .trial(daysRemaining: Int(ceil(remaining / 86400)))
    }
}
