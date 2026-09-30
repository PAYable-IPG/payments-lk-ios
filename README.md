# Payments.lk iOS SDK

Swift Package for taking payments with the Payments.lk hosted checkout from an iOS or macOS app.

The SDK opens the Payments.lk hosted checkout page in a system sheet (`ASWebAuthenticationSession`), waits for the page to redirect back to your app, and gives you a `CheckoutResult` with the checkout id and how the checkout ended. It has no third party dependencies.

The SDK never talks to the Payments.lk API and never needs an API key. Your backend creates the checkout, and your backend confirms the payment.

## Requirements

- iOS 15 or later, or macOS 12 or later
- Swift 5.9 or later (Xcode 15 or later)
- A backend that can call the Payments.lk API with your secret key

## Installation (Swift Package Manager)

In Xcode: File, Add Package Dependencies, enter `https://github.com/PAYable-IPG/payments-lk-ios`, choose Up to Next Major Version from `0.1.1`, then add the `PaymentsLk` library to your app target.

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PAYable-IPG/payments-lk-ios.git", from: "0.1.1"),
],
targets: [
    .target(name: "MyShop", dependencies: [
        .product(name: "PaymentsLk", package: "payments-lk-ios"),
    ]),
]
```

Each version is a tag on that repository, and its release notes are in `CHANGELOG.md`.

## How it works

1. The app asks its own backend for a checkout.
2. The backend creates the checkout with its secret key and returns `url` and `id` to the app.
3. The app calls `PaymentsLkCheckout.present(...)` with that `url`.
4. The customer pays (or not) on the hosted page. When the checkout ends, the page redirects to your `successUrl` or `cancelUrl`, and the sheet closes.
5. The app shows a pending or result screen, and asks its backend to confirm the payment.

## Step 1: create the checkout on your backend

Secret keys (`sk_test_...`, `sk_live_...`) must never be shipped in an app. Only your backend holds them.

Your backend calls `POST https://api.payments.lk/v1/checkouts`:

```sh
curl https://api.payments.lk/v1/checkouts \
  -H "Authorization: Bearer $PAYMENTS_LK_SECRET_KEY" \
  -H "Idempotency-Key: order-1042-attempt-1" \
  -H "Content-Type: application/json" \
  -d '{
    "amountCents": 250000,
    "description": "Order 1042",
    "reference": "order-1042",
    "successUrl": "myshop://payments-lk/return",
    "cancelUrl": "myshop://payments-lk/return"
  }'
```

- `amountCents` is the amount in cents (250000 is LKR 2,500.00).
- `reference` is optional.
- For an app, `successUrl` and `cancelUrl` use your app's own URL scheme, for example `myshop://payments-lk/return`. You can use the same URL for both, or different paths.
- Use a new `Idempotency-Key` per checkout attempt so retries do not create duplicates.

The response contains `url` (the https hosted checkout page on payments.lk) and `id` (`chk_` followed by lowercase letters and digits). Return both to the app, for example:

```json
{ "url": "https://payments.lk/...", "id": "chk_8f3k2m9q" }
```

When the checkout ends, the hosted page sends the browser to `successUrl` (payment succeeded) or `cancelUrl` (failed, canceled or expired), keeps any query parameters you put there, and appends two more:

```
myshop://payments-lk/return?checkout=chk_8f3k2m9q&status=succeeded
```

`status` is one of `succeeded`, `failed`, `canceled`, `expired`.

## Saving a card for later

The checkout can ask the customer to keep their card, so your server charges it again later without them present: a subscription, instalments, or one tap repeat orders. Your server sets `saveCard` when it creates the checkout, and the customer decides on the hosted page; the app does nothing differently, and no card number ever reaches it.

```json
{ "amountCents": 250000, "description": "First month", "saveCard": true, "customer": { "name": "Ruwan", "email": "ruwan@example.lk" } }
```

When that first payment succeeds, your server receives the `card.saved` webhook with a card id (`card_...`) to keep against the customer, and charges it later with `POST /v1/cards/{id}/charge`. The card carries the month it expires and what the customer agreed to, so your server can show both. Only that first payment asks the cardholder to authenticate: a later charge is made without them, so a bank that insists on a check declines it, and you send the customer back to a checkout.

Saved cards use Payable's Advanced plan, switched on in the dashboard. The steps are at https://payments.lk/developers/guide#card-on-file.

## Step 2: present the checkout in the app

```swift
import PaymentsLk
import SwiftUI

struct PayButton: View {
    let orderId: String
    @State private var checkout = PaymentsLkCheckout()
    @State private var message = ""

    var body: some View {
        VStack {
            Button("Pay") { Task { await pay() } }
            Text(message)
        }
    }

    @MainActor
    private func pay() async {
        do {
            // Your own backend endpoint, which calls POST /v1/checkouts.
            let created = try await MyBackend.createCheckout(orderId: orderId)

            let result = try await checkout.present(
                checkoutURL: created.url,
                callbackScheme: "myshop"
            )

            switch result.status {
            case .succeeded:
                // Not proof of payment yet. Confirm on the server.
                message = "Confirming payment..."
                let paid = try await MyBackend.confirmCheckout(id: created.id)
                message = paid ? "Payment received" : "Payment not confirmed yet"
            case .failed:
                message = "The payment failed. Please try again."
            case .canceled:
                message = "Payment canceled."
            case .expired:
                message = "The checkout expired. Please start again."
            case .dismissed:
                // Closed before any redirect. The customer may still have paid
                // (for example the sheet was closed right after paying), so check
                // the server before offering to pay again.
                message = "Checkout closed."
            }
        } catch let error as PaymentsLkError {
            message = error.localizedDescription
        } catch is CancellationError {
            // The calling task was cancelled, the sheet has been closed.
        } catch {
            message = "Something went wrong: \(error.localizedDescription)"
        }
    }
}
```

`present(checkoutURL:callbackScheme:anchor:prefersEphemeralWebBrowserSession:)`:

- `checkoutURL`: the `url` from your backend. It must be https. Plain http is accepted only on `localhost` or `127.0.0.1`, for local development. URLs with a user or password are rejected.
- `callbackScheme`: your app scheme, the same one used in `successUrl` and `cancelUrl`. It must match `^[a-z][a-z0-9+.-]{2,39}$` and cannot be `http`, `https`, `file`, `javascript`, `data` or `about`.
- `anchor`: the window to present from. When omitted, the SDK uses the key window of the foreground scene (UIKit) or the key window of the app (AppKit). In an app extension, pass the anchor yourself.
- `prefersEphemeralWebBrowserSession`: pass `true` to keep the checkout from sharing cookies with the user's browser.

### Results

| `status` | Meaning | `checkoutId` |
| --- | --- | --- |
| `.succeeded` | The hosted page reported success. Confirm on the server before fulfilling. | `chk_...` |
| `.failed` | The payment attempt failed. | `chk_...` |
| `.canceled` | The customer canceled on the hosted page. | `chk_...` |
| `.expired` | The checkout expired. | `chk_...` |
| `.dismissed` | The customer closed the sheet before any redirect. | `nil` |

### Errors

`present` throws `PaymentsLkError`:

- `.insecureCheckoutURL`: the checkout URL is not allowed (see above).
- `.invalidCallbackScheme`: the callback scheme is not allowed.
- `.alreadyPresenting`: this `PaymentsLkCheckout` is already showing a checkout. Only one runs at a time.
- `.couldNotStart`: the system session could not start, for example no window was available.
- `.unexpectedCallback`: the sheet returned a URL that is not a valid Payments.lk redirect.

If the calling task is cancelled, the sheet is closed and `present` throws `CancellationError`. Any other system error from `ASWebAuthenticationSession` is rethrown unchanged.

You can also parse a redirect URL yourself with `CheckoutResult.parse(url:callbackScheme:)`. It is strict: the scheme must match, `checkout` must match `^chk_[0-9a-z]{1,64}$`, `status` must be one of the four redirect values, each must appear exactly once, and anything else returns `nil`. It never returns `.dismissed`.

## Step 3: confirm the payment on your server

The redirect is not proof of payment. Anyone can open `myshop://payments-lk/return?checkout=chk_x&status=succeeded` on a device. Never fulfill an order, unlock content or mark an invoice paid because the app saw `.succeeded`.

Instead, the app asks your backend to confirm, and your backend does one of these:

- Calls `GET https://api.payments.lk/v1/checkouts/{id}` with its secret key and trusts `payment.status` in the response.
- Waits for the signed `payment.succeeded` webhook, verifies the signature, and fulfills the order from there.

```sh
curl https://api.payments.lk/v1/checkouts/chk_8f3k2m9q \
  -H "Authorization: Bearer $PAYMENTS_LK_SECRET_KEY"
```

Webhooks are the most reliable source, because they also arrive when the customer closes the app or loses connection right after paying. The app can show a pending state and poll your backend until it knows.

## Subscriptions

A subscription's first payment is a hosted checkout, so the app presents it exactly as in step 2. Your backend creates the subscription instead of a checkout, with `successUrl` and `cancelUrl` in your app's scheme, and answers `subscription.checkoutUrl` (nil when the customer already has a card on file, in which case the first period was charged at once).

Two more pages have no checkout id to return, so `present` is not for them. Open them in `SFSafariViewController` or your own `ASWebAuthenticationSession`, and let your backend, which receives the webhooks, tell the app what changed:

```swift
// A subscription link made in the dashboard, with one of its plans chosen first. Give the link a success
// address in your app's scheme when you make it, so the customer comes back after paying.
if let url = PaymentsLkValidation.subscriptionLinkURL(code: "LINKCODE", plan: "price_0123456789abcdefghij") {
    present(SFSafariViewController(url: url), animated: true)
}

// The customer portal, from a session your backend created with returnUrl in your app's scheme.
present(SFSafariViewController(url: session.url), animated: true)
```

## Callback scheme: no URL type registration needed

`ASWebAuthenticationSession` catches the redirect to your callback scheme inside the sheet itself, so you do not need to add the scheme to `CFBundleURLTypes` (URL Types in Xcode) for this flow. Register it only if you also want other apps or links to open your app with that scheme.

## Development

The package builds with the Swift toolchain on macOS:

```sh
cd sdks/ios
swift build
swift test
```

Tests use Swift Testing (`import Testing`). XCTest is not used because it is not shipped with the Command Line Tools, while Swift Testing is, so `swift test` works both with Xcode and with the Command Line Tools alone (Swift 6 toolchain or later).

`swift build` on a Mac builds the macOS variant. Building for iOS needs Xcode and the iOS SDK, for example:

```sh
xcodebuild -scheme PaymentsLk -destination 'generic/platform=iOS Simulator' build
```

`CheckoutResult` and `PaymentsLkValidation` are plain Foundation code and are fully covered by tests. `PaymentsLkCheckout` presents system UI, so it is not exercised by the unit tests; try it in a sample app against a local or test mode checkout.
