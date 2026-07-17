import Foundation

/// Polar.sh organization/product identifiers and endpoints.
///
/// These are placeholders until the Polar.sh organization/product are
/// created. Values are read from Info.plist so they can be swapped without
/// touching code — replace the `Polar*` keys in Sources/Hotbar/Info.plist.
enum PolarConfig {
    static var organizationID: String {
        infoString(for: "PolarOrganizationID") ?? "REPLACE_ME_ORGANIZATION_ID"
    }

    static var productID: String {
        infoString(for: "PolarProductID") ?? "REPLACE_ME_PRODUCT_ID"
    }

    static var checkoutURL: URL {
        let fallback = "https://buy.polar.sh/REPLACE_ME_PRODUCT_ID"
        return url(infoString(for: "PolarCheckoutURL") ?? fallback)
    }

    static var apiBaseURL: URL {
        let fallback = "https://api.polar.sh/v1"
        return url(infoString(for: "PolarAPIBaseURL") ?? fallback)
    }

    private static func infoString(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// `URL(fileURLWithPath:)` never fails, so this never actually falls
    /// through to it for our well-formed literals — it just avoids a
    /// force-unwrap of `URL(string:)`.
    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}
