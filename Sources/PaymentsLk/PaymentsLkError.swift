import Foundation

/// Errors thrown by `PaymentsLkCheckout.present(...)`.
public enum PaymentsLkError: Error, Equatable, Hashable, Sendable {
    /// The checkout URL is not https (or http on localhost or 127.0.0.1),
    /// or it carries a user or password.
    case insecureCheckoutURL
    /// The callback scheme does not match `^[a-z][a-z0-9+.-]{2,39}$`
    /// or is a reserved scheme such as `https`.
    case invalidCallbackScheme
    /// A checkout is already being presented by this instance.
    case alreadyPresenting
    /// The system web authentication session could not be started,
    /// for example because no presentation anchor was available.
    case couldNotStart
    /// The session returned a callback URL that is not a valid Payments.lk redirect.
    case unexpectedCallback
}

extension PaymentsLkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .insecureCheckoutURL:
            return "The checkout URL must use https (http is allowed only on localhost or 127.0.0.1) and must not contain credentials."
        case .invalidCallbackScheme:
            return "The callback scheme is invalid. Use a lowercase app scheme such as myshop."
        case .alreadyPresenting:
            return "A Payments.lk checkout is already being presented."
        case .couldNotStart:
            return "The Payments.lk checkout could not be started."
        case .unexpectedCallback:
            return "The Payments.lk checkout returned an unexpected callback URL."
        }
    }
}
