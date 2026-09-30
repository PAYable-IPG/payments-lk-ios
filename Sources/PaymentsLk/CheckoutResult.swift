import Foundation

/// The outcome of a hosted checkout, as reported by the redirect back to the app.
///
/// A result is a hint for the user interface only. It is not proof of payment:
/// always confirm with your backend, which calls `GET /v1/checkouts/{id}` and
/// trusts `payment.status`, or waits for the signed `payment.succeeded` webhook.
public struct CheckoutResult: Equatable, Hashable, Sendable {

    /// How the checkout ended.
    public enum Status: String, CaseIterable, Equatable, Hashable, Sendable {
        /// The hosted page reported a successful payment.
        case succeeded
        /// The payment attempt failed.
        case failed
        /// The customer canceled on the hosted page.
        case canceled
        /// The checkout expired before it was completed.
        case expired
        /// The customer closed the sheet before any redirect happened.
        /// Never produced by `CheckoutResult.parse(url:callbackScheme:)`.
        case dismissed

        /// The statuses the hosted page can put in the `status` query parameter.
        public static let redirectStatuses: Set<Status> = [.succeeded, .failed, .canceled, .expired]
    }

    /// How the checkout ended.
    public let status: Status

    /// The checkout id (`chk_...`). `nil` only when `status` is `.dismissed`.
    public let checkoutId: String?

    /// The result used when the customer closes the sheet before any redirect.
    public static let dismissed = CheckoutResult(uncheckedStatus: .dismissed, checkoutId: nil)

    /// Creates a result, enforcing the invariant that `checkoutId` is `nil`
    /// exactly when `status` is `.dismissed`, and that any id is well formed.
    /// Useful for tests and previews in the host app.
    public init?(status: Status, checkoutId: String?) {
        if status == .dismissed {
            guard checkoutId == nil else { return nil }
        } else {
            guard let checkoutId, PaymentsLkValidation.isValidCheckoutId(checkoutId) else { return nil }
        }
        self.init(uncheckedStatus: status, checkoutId: checkoutId)
    }

    private init(uncheckedStatus: Status, checkoutId: String?) {
        self.status = uncheckedStatus
        self.checkoutId = checkoutId
    }

    /// Strictly parses a redirect URL produced by the hosted checkout page.
    ///
    /// Returns `nil` unless all of the following hold:
    /// - the URL scheme equals `callbackScheme`, compared case insensitively,
    /// - the query has exactly one `checkout` parameter matching `^chk_[0-9a-z]{1,64}$`,
    /// - the query has exactly one `status` parameter equal to `succeeded`,
    ///   `failed`, `canceled` or `expired`.
    ///
    /// Other query parameters (for example ones your backend put in the
    /// success or cancel URL) are ignored. This never returns `.dismissed`.
    public static func parse(url: URL, callbackScheme: String) -> CheckoutResult? {
        guard let scheme = url.scheme,
              !callbackScheme.isEmpty,
              scheme.lowercased() == callbackScheme.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else {
            return nil
        }

        let checkoutItems = items.filter { $0.name == "checkout" }
        let statusItems = items.filter { $0.name == "status" }
        guard checkoutItems.count == 1,
              statusItems.count == 1,
              let checkoutId = checkoutItems[0].value,
              let rawStatus = statusItems[0].value,
              PaymentsLkValidation.isValidCheckoutId(checkoutId),
              let status = Status(rawValue: rawStatus),
              Status.redirectStatuses.contains(status)
        else {
            return nil
        }

        return CheckoutResult(uncheckedStatus: status, checkoutId: checkoutId)
    }
}
