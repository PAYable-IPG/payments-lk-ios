#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
import AuthenticationServices
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Presents a Payments.lk hosted checkout in a system web authentication sheet
/// and returns how it ended.
///
/// The checkout URL must come from your backend, which creates the checkout with
/// its secret key. Never put a secret key (`sk_test_...`, `sk_live_...`) in an app.
///
/// The returned `CheckoutResult` is not proof of payment. Confirm with your
/// backend before fulfilling the order.
@MainActor
public final class PaymentsLkCheckout {

    private var session: ASWebAuthenticationSession?
    private var contextProvider: AnchorContextProvider?
    private var isPresenting = false

    public init() {}

    /// Presents the hosted checkout and waits for it to finish.
    ///
    /// - Parameters:
    ///   - checkoutURL: The `url` returned by your backend for the checkout.
    ///   - callbackScheme: Your app's URL scheme, the same one used in the
    ///     checkout's `successUrl` and `cancelUrl` (for example `myshop`).
    ///   - anchor: The window to present from. Defaults to the key window.
    ///   - prefersEphemeralWebBrowserSession: Pass `true` to avoid sharing
    ///     cookies with the user's browser.
    /// - Returns: The redirect result, or `.dismissed` if the customer closed
    ///   the sheet before any redirect.
    /// - Throws: `PaymentsLkError` for invalid input, a concurrent presentation,
    ///   a session that cannot start, or an unexpected callback URL.
    ///   `CancellationError` if the calling task is cancelled (the sheet is closed).
    ///   Any other system error from the session is rethrown unchanged.
    public func present(
        checkoutURL: URL,
        callbackScheme: String,
        anchor: ASPresentationAnchor? = nil,
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> CheckoutResult {
        guard PaymentsLkValidation.isAllowedCheckoutURL(checkoutURL) else {
            throw PaymentsLkError.insecureCheckoutURL
        }
        guard PaymentsLkValidation.isValidCallbackScheme(callbackScheme) else {
            throw PaymentsLkError.invalidCallbackScheme
        }
        guard !isPresenting else {
            throw PaymentsLkError.alreadyPresenting
        }
        try Task.checkCancellation()
        guard let resolvedAnchor = anchor ?? Self.defaultAnchor() else {
            throw PaymentsLkError.couldNotStart
        }

        isPresenting = true
        defer {
            session = nil
            contextProvider = nil
            isPresenting = false
        }

        let provider = AnchorContextProvider(anchor: resolvedAnchor)
        contextProvider = provider

        let result: CheckoutResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CheckoutResult, Error>) in
                let box = ContinuationBox(continuation)
                let newSession = Self.makeSession(url: checkoutURL, callbackScheme: callbackScheme) { callbackURL, error in
                    box.resume(with: Self.outcome(callbackURL: callbackURL, error: error, callbackScheme: callbackScheme))
                }
                newSession.presentationContextProvider = provider
                newSession.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                session = newSession
                if !newSession.start() {
                    box.resume(with: .failure(PaymentsLkError.couldNotStart))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.session?.cancel()
            }
        }

        if result.status == .dismissed && Task.isCancelled {
            throw CancellationError()
        }
        return result
    }

    // MARK: - Internals

    private static func makeSession(
        url: URL,
        callbackScheme: String,
        completion: @escaping @Sendable (URL?, Error?) -> Void
    ) -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme, completionHandler: completion)
    }

    nonisolated static func outcome(
        callbackURL: URL?,
        error: Error?,
        callbackScheme: String
    ) -> Result<CheckoutResult, Error> {
        if let error {
            if let sessionError = error as? ASWebAuthenticationSessionError {
                switch sessionError.code {
                case .canceledLogin:
                    return .success(.dismissed)
                case .presentationContextNotProvided, .presentationContextInvalid:
                    return .failure(PaymentsLkError.couldNotStart)
                @unknown default:
                    return .failure(error)
                }
            }
            return .failure(error)
        }
        guard let callbackURL,
              let result = CheckoutResult.parse(url: callbackURL, callbackScheme: callbackScheme)
        else {
            return .failure(PaymentsLkError.unexpectedCallback)
        }
        return .success(result)
    }

    private static func defaultAnchor() -> ASPresentationAnchor? {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        for scene in active + scenes {
            if let window = scene.keyWindow {
                return window
            }
        }
        return active.first?.windows.first ?? scenes.first?.windows.first
        #elseif canImport(AppKit)
        let app = NSApplication.shared
        return app.keyWindow ?? app.mainWindow ?? app.windows.first
        #else
        return nil
        #endif
    }
}

/// Supplies a fixed window to the session. Held strongly by `PaymentsLkCheckout`
/// because the session only keeps a weak reference to its context provider.
private final class AnchorContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

/// Resumes a continuation at most once, from any thread.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CheckoutResult, Error>?

    init(_ continuation: CheckedContinuation<CheckoutResult, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<CheckoutResult, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
#endif
