import XCTest
@testable import Hotbar

final class PolarLicenseClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubURLProtocol.stub = nil
        session = nil
        super.tearDown()
    }

    private static let baseURL = URL(string: "https://api.polar.sh/v1") ?? URL(fileURLWithPath: "/")

    private func makeClient() -> PolarLicenseClient {
        PolarLicenseClient(
            baseURL: Self.baseURL,
            organizationID: "org-123",
            session: session
        )
    }

    func testActivateSendsOrganizationIDAndLabel() async throws {
        StubURLProtocol.stub = { request in
            XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/activate")
            let body = try XCTUnwrap(request.decodedBody())
            XCTAssertEqual(body["key"], "GOOD-KEY")
            XCTAssertEqual(body["organization_id"], "org-123")
            XCTAssertEqual(body["label"], "Test Mac")
            return (200, #"{"id": "activation-1", "label": "Test Mac"}"#)
        }

        let response = try await makeClient().activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        XCTAssertTrue(response.activated)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.instance, LicenseInstance(id: "activation-1", name: "Test Mac"))
    }

    func testActivateSurfacesPolarErrorDetailOnFailure() async throws {
        StubURLProtocol.stub = { _ in
            (404, #"{"error": "ResourceNotFound", "detail": "This license key is not valid."}"#)
        }

        let response = try await makeClient().activate(licenseKey: "BAD-KEY", instanceName: "Test Mac")

        XCTAssertFalse(response.activated)
        XCTAssertEqual(response.error, "This license key is not valid.")
        XCTAssertNil(response.instance)
    }

    func testValidateSendsActivationID() async throws {
        StubURLProtocol.stub = { request in
            XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/validate")
            let body = try XCTUnwrap(request.decodedBody())
            XCTAssertEqual(body["activation_id"], "activation-1")
            return (200, #"{"status": "granted"}"#)
        }

        let response = try await makeClient().validate(licenseKey: "GOOD-KEY", instanceID: "activation-1")

        XCTAssertTrue(response.valid)
        XCTAssertNil(response.error)
    }

    func testValidateReturnsInvalidOnNon200() async throws {
        StubURLProtocol.stub = { _ in
            (404, #"{"error": "ResourceNotFound", "detail": "Activation not found."}"#)
        }

        let response = try await makeClient().validate(licenseKey: "GOOD-KEY", instanceID: "missing")

        XCTAssertFalse(response.valid)
        XCTAssertEqual(response.error, "Activation not found.")
    }
}

private final class StubURLProtocol: URLProtocol {
    static var stub: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = StubURLProtocol.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (statusCode, body) = try stub(request)
            guard let requestURL = request.url,
                  let response = HTTPURLResponse(
                      url: requestURL,
                      statusCode: statusCode,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func decodedBody() -> [String: String]? {
        guard let data = httpBody ?? httpBodyStream?.readAll() else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}

private extension InputStream {
    func readAll() -> Data {
        open()
        defer { close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while hasBytesAvailable {
            let read = self.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
