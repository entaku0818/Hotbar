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

/// Talks to the Polar.sh customer-portal License Key API (activate/validate).
/// See: https://polar.sh/docs/features/benefits/license-keys
protocol LicenseClient {
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationResponse
    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidationResponse
}

/// Raw shape returned by Polar's `license-keys/activate` on success (200).
private struct PolarActivationPayload: Decodable {
    let id: String
    let label: String
}

/// Raw shape returned by Polar on failure (404/422): `{"error": ..., "detail": ...}`.
private struct PolarErrorPayload: Decodable {
    let detail: String
}

final class PolarLicenseClient: LicenseClient {
    private let baseURL: URL
    private let organizationID: String
    private let session: URLSession

    init(
        baseURL: URL = PolarConfig.apiBaseURL,
        organizationID: String = PolarConfig.organizationID,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.organizationID = organizationID
        self.session = session
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationResponse {
        let (data, response) = try await post(path: "customer-portal/license-keys/activate", body: [
            "key": licenseKey,
            "organization_id": organizationID,
            "label": instanceName
        ])

        guard response.statusCode == 200 else {
            return LicenseActivationResponse(activated: false, error: errorMessage(from: data), instance: nil)
        }
        let payload: PolarActivationPayload = try decode(data)
        return LicenseActivationResponse(
            activated: true,
            error: nil,
            instance: LicenseInstance(id: payload.id, name: payload.label)
        )
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidationResponse {
        let (data, response) = try await post(path: "customer-portal/license-keys/validate", body: [
            "key": licenseKey,
            "organization_id": organizationID,
            "activation_id": instanceID
        ])

        guard response.statusCode == 200 else {
            return LicenseValidationResponse(valid: false, error: errorMessage(from: data))
        }
        return LicenseValidationResponse(valid: true, error: nil)
    }

    private func post(path: String, body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseClientError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LicenseClientError.invalidResponse
        }
    }

    private func errorMessage(from data: Data) -> String {
        (try? JSONDecoder().decode(PolarErrorPayload.self, from: data))?.detail
            ?? "This license key could not be activated."
    }
}
