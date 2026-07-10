import Foundation

struct LicenseInstance: Decodable, Equatable {
    let id: String
    let name: String
}

struct LicenseActivationResponse: Decodable, Equatable {
    let activated: Bool
    let error: String?
    let instance: LicenseInstance?
}

struct LicenseValidationResponse: Decodable, Equatable {
    let valid: Bool
    let error: String?
}

enum LicenseClientError: Error, LocalizedError, Equatable {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not reach the license server. Please check your connection and try again."
        }
    }
}

/// Talks to the Lemon Squeezy License API (activate/validate).
/// See: https://docs.lemonsqueezy.com/help/licensing/license-api
protocol LicenseClient {
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationResponse
    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidationResponse
}

final class LemonSqueezyLicenseClient: LicenseClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = LemonSqueezyConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationResponse {
        try await post(path: "licenses/activate", body: [
            "license_key": licenseKey,
            "instance_name": instanceName
        ])
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidationResponse {
        try await post(path: "licenses/validate", body: [
            "license_key": licenseKey,
            "instance_id": instanceID
        ])
    }

    private func post<T: Decodable>(path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await session.data(for: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LicenseClientError.invalidResponse
        }
    }
}
