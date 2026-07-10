import Foundation

enum LicenseStatus: Equatable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed
}

extension Notification.Name {
    /// Posted when a gated feature (e.g. the overlay) is requested but the
    /// trial has expired and no license is active.
    static let licenseGateRequested = Notification.Name("licenseGateRequested")
}

/// Tracks the 14-day free trial and Lemon Squeezy license activation state.
///
/// Trial/license state is stored in UserDefaults for v1 (simple, and
/// injectable for tests). A future revision could move the license key to
/// the Keychain for stronger persistence across reinstalls.
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60

    @Published private(set) var status: LicenseStatus
    @Published var activationErrorMessage: String?

    private let defaults: UserDefaults
    private let client: LicenseClient
    private let now: () -> Date

    private enum Keys {
        static let trialStartDate = "licenseTrialStartDate"
        static let licenseKey = "licenseKey"
        static let instanceID = "licenseInstanceID"
    }

    init(
        defaults: UserDefaults = .standard,
        client: LicenseClient = LemonSqueezyLicenseClient(),
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

    /// True when a gated feature should be blocked (trial over, no license).
    var isGated: Bool {
        status == .trialExpired
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
            refreshStatus()
        } catch {
            activationErrorMessage = error.localizedDescription
        }
    }

    /// Clears the stored license, reverting to trial/expired state. Exposed
    /// for debugging and tests — not wired to any menu item in v1.
    func deactivate() {
        defaults.removeObject(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.instanceID)
        refreshStatus()
    }

    private static func computeStatus(defaults: UserDefaults, now: Date) -> LicenseStatus {
        if defaults.string(forKey: Keys.licenseKey) != nil {
            return .licensed
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
