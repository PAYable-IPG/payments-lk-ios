import Foundation

/// Input checks used by the SDK before a checkout is presented.
/// They are public so apps and tests can run the same checks.
public enum PaymentsLkValidation {

    /// Schemes that can never be used as an app callback scheme.
    public static let reservedCallbackSchemes: Set<String> = [
        "http", "https", "file", "javascript", "data", "about",
    ]

    /// Returns `true` only for URLs that are safe to open as a hosted checkout:
    /// - `https` with a host and no user or password, or
    /// - `http` on `localhost` or `127.0.0.1` with no user or password, for local development.
    public static func isAllowedCheckoutURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return false
        }

        switch scheme {
        case "https":
            return true
        case "http":
            return host == "localhost" || host == "127.0.0.1"
        default:
            return false
        }
    }

    /// The address of a subscription link on the Payments.lk site, with the
    /// plan to choose first when one is named: what an app opens for a
    /// customer to pick a plan and pay the first period. `nil` when the code
    /// or the plan id is not shaped like one, so a wrong value opens nothing.
    ///
    /// The link's success address, set in the dashboard to your app's scheme,
    /// brings the customer back; open the URL with `SFSafariViewController`
    /// or `ASWebAuthenticationSession` and treat any return as a reason to
    /// ask your backend, never as proof of payment.
    public static func subscriptionLinkURL(code: String, plan: String? = nil, locale: String? = nil, site: URL? = nil) -> URL? {
        guard isLinkCode(code) else { return nil }
        if let plan, !isPriceId(plan) { return nil }
        guard let base = site ?? URL(string: "https://payments.lk"),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil
        else { return nil }
        var path = ""
        if let locale, locale == "si" || locale == "ta" { path += "/" + locale }
        path += "/s/" + code
        components.path = path
        components.query = nil
        components.fragment = nil
        if let plan { components.queryItems = [URLQueryItem(name: "plan", value: plan)] }
        return components.url
    }

    /// A subscription link's code: 8 to 64 letters, digits, `_` or `-`.
    public static func isLinkCode(_ code: String) -> Bool {
        let bytes = Array(code.utf8)
        guard (8...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { isLowerAlpha($0) || isUpperAlpha($0) || isDigit($0) || $0 == UInt8(ascii: "_") || $0 == UInt8(ascii: "-") }
    }

    /// A price id: `price_` then 20 to 32 lower case letters or digits.
    public static func isPriceId(_ id: String) -> Bool {
        let prefix = "price_"
        guard id.hasPrefix(prefix) else { return false }
        let rest = Array(id.dropFirst(prefix.count).utf8)
        guard (20...32).contains(rest.count) else { return false }
        return rest.allSatisfy { isLowerAlpha($0) || isDigit($0) }
    }

    private static func isUpperAlpha(_ byte: UInt8) -> Bool {
        return byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")
    }

    /// Returns `true` when `scheme` matches `^[a-z][a-z0-9+.-]{2,39}$`
    /// and is not one of `reservedCallbackSchemes`.
    public static func isValidCallbackScheme(_ scheme: String) -> Bool {
        let bytes = Array(scheme.utf8)
        guard (3...40).contains(bytes.count), isLowerAlpha(bytes[0]) else {
            return false
        }
        for byte in bytes.dropFirst() {
            let allowed = isLowerAlpha(byte)
                || isDigit(byte)
                || byte == UInt8(ascii: "+")
                || byte == UInt8(ascii: ".")
                || byte == UInt8(ascii: "-")
            guard allowed else { return false }
        }
        return !reservedCallbackSchemes.contains(scheme)
    }

    /// Returns `true` when `id` matches `^chk_[0-9a-z]{1,64}$`.
    public static func isValidCheckoutId(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        let prefix = Array("chk_".utf8)
        guard bytes.count > prefix.count,
              bytes.count <= prefix.count + 64,
              Array(bytes.prefix(prefix.count)) == prefix
        else {
            return false
        }
        return bytes.dropFirst(prefix.count).allSatisfy { isLowerAlpha($0) || isDigit($0) }
    }

    private static func isLowerAlpha(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
}
