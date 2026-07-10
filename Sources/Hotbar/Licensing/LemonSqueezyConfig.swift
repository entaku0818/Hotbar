import Foundation

/// Lemon Squeezy store/product identifiers and endpoints.
///
/// These are placeholders until the Lemon Squeezy store/product are created.
/// Values are read from Info.plist so they can be swapped without touching
/// code — replace the `LemonSqueezy*` keys in Sources/Hotbar/Info.plist.
enum LemonSqueezyConfig {
    static var storeID: String {
        infoString(for: "LemonSqueezyStoreID") ?? "REPLACE_ME_STORE_ID"
    }

    static var productID: String {
        infoString(for: "LemonSqueezyProductID") ?? "REPLACE_ME_PRODUCT_ID"
    }

    static var checkoutURL: URL {
        let fallback = "https://REPLACE_ME.lemonsqueezy.com/checkout/buy/REPLACE_ME_VARIANT_ID"
        return url(infoString(for: "LemonSqueezyCheckoutURL") ?? fallback)
    }

    static var apiBaseURL: URL {
        let fallback = "https://api.lemonsqueezy.com/v1"
        return url(infoString(for: "LemonSqueezyAPIBaseURL") ?? fallback)
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
