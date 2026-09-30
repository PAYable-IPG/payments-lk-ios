import Foundation
import Testing
@testable import PaymentsLk

private func makeURL(_ string: String) throws -> URL {
    try #require(URL(string: string), "Could not build URL from \(string)")
}

@Suite("CheckoutResult.parse")
struct CheckoutResultParseTests {

    @Test("parses every redirect status", arguments: ["succeeded", "failed", "canceled", "expired"])
    func parsesEveryRedirectStatus(status: String) throws {
        let result = CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?checkout=chk_abc123&status=\(status)"),
            callbackScheme: "myshop"
        )
        #expect(result?.status.rawValue == status)
        #expect(result?.checkoutId == "chk_abc123")
    }

    @Test("parameter order does not matter")
    func parameterOrderDoesNotMatter() throws {
        let result = CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?status=succeeded&checkout=chk_0z9"),
            callbackScheme: "myshop"
        )
        #expect(result != nil)
        #expect(result == CheckoutResult(status: .succeeded, checkoutId: "chk_0z9"))
    }

    @Test("scheme is compared case insensitively")
    func schemeComparedCaseInsensitively() throws {
        #expect(CheckoutResult.parse(
            url: try makeURL("MyShop://payments-lk/return?checkout=chk_abc&status=failed"),
            callbackScheme: "myshop"
        ) != nil)
        #expect(CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?checkout=chk_abc&status=failed"),
            callbackScheme: "MYSHOP"
        ) != nil)
    }

    @Test("extra query parameters are kept and ignored")
    func extraQueryParametersAreKeptAndIgnored() throws {
        let result = CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?order=42&cart=a%20b&checkout=chk_abc&status=canceled"),
            callbackScheme: "myshop"
        )
        #expect(result?.status == .canceled)
        #expect(result?.checkoutId == "chk_abc")
    }

    @Test("wrong scheme returns nil", arguments: [
        ("othershop://payments-lk/return?checkout=chk_abc&status=succeeded", "myshop"),
        ("https://payments.lk/return?checkout=chk_abc&status=succeeded", "myshop"),
        ("myshopx://payments-lk/return?checkout=chk_abc&status=succeeded", "myshop"),
        ("myshop://payments-lk/return?checkout=chk_abc&status=succeeded", "myshopx"),
        ("myshop://payments-lk/return?checkout=chk_abc&status=succeeded", ""),
    ])
    func wrongSchemeReturnsNil(url: String, callbackScheme: String) throws {
        #expect(CheckoutResult.parse(url: try makeURL(url), callbackScheme: callbackScheme) == nil)
    }

    @Test("bad checkout id returns nil", arguments: [
        "",
        "chk_",
        "chk",
        "abc123",
        "CHK_abc",
        "chk_ABC",
        "chk_abc-123",
        "chk_abc_123",
        "chk_abc%20",
        "pay_abc123",
        " chk_abc",
        "chk_\u{0430}bc",
        "chk_" + String(repeating: "a", count: 65),
    ])
    func badCheckoutIdReturnsNil(id: String) throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let result = CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?checkout=\(encoded)&status=succeeded"),
            callbackScheme: "myshop"
        )
        #expect(result == nil)
    }

    @Test("checkout id of 64 characters is accepted")
    func maxLengthCheckoutIdAccepted() throws {
        let id = "chk_" + String(repeating: "a", count: 64)
        let result = CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?checkout=\(id)&status=succeeded"),
            callbackScheme: "myshop"
        )
        #expect(result?.checkoutId == id)
    }

    @Test("bad status returns nil", arguments: [
        "", "dismissed", "SUCCEEDED", "Succeeded", "success", "paid", "pending", "cancelled",
    ])
    func badStatusReturnsNil(status: String) throws {
        let result = CheckoutResult.parse(
            url: try makeURL("myshop://payments-lk/return?checkout=chk_abc&status=\(status)"),
            callbackScheme: "myshop"
        )
        #expect(result == nil)
    }

    @Test("missing parameters return nil", arguments: [
        "myshop://payments-lk/return",
        "myshop://payments-lk/return?",
        "myshop://payments-lk/return?checkout=chk_abc",
        "myshop://payments-lk/return?status=succeeded",
        "myshop://payments-lk/return?checkout&status=succeeded",
        "myshop://payments-lk/return?checkout=chk_abc&status",
        "myshop://payments-lk/return#checkout=chk_abc&status=succeeded",
    ])
    func missingParametersReturnNil(url: String) throws {
        #expect(CheckoutResult.parse(url: try makeURL(url), callbackScheme: "myshop") == nil)
    }

    @Test("duplicate parameters return nil", arguments: [
        "myshop://payments-lk/return?checkout=chk_abc&checkout=chk_def&status=succeeded",
        "myshop://payments-lk/return?checkout=chk_abc&status=failed&status=succeeded",
        "myshop://payments-lk/return?checkout=chk_abc&checkout=chk_abc&status=succeeded",
        "myshop://payments-lk/return?checkout=chk_abc&status=succeeded&status=succeeded",
    ])
    func duplicateParametersReturnNil(url: String) throws {
        #expect(CheckoutResult.parse(url: try makeURL(url), callbackScheme: "myshop") == nil)
    }

    @Test("parse never produces dismissed")
    func parseNeverProducesDismissed() throws {
        let candidates = [
            "myshop://payments-lk/return?checkout=chk_abc&status=dismissed",
            "myshop://payments-lk/return?status=dismissed",
            "myshop://payments-lk/return",
        ] + CheckoutResult.Status.allCases.map {
            "myshop://payments-lk/return?checkout=chk_abc&status=\($0.rawValue)"
        }
        for string in candidates {
            let result = CheckoutResult.parse(url: try makeURL(string), callbackScheme: "myshop")
            #expect(result?.status != .dismissed, "parse produced dismissed for \(string)")
        }
        #expect(!CheckoutResult.Status.redirectStatuses.contains(.dismissed))
    }

    @Test("failable init enforces the checkoutId invariant")
    func failableInitEnforcesInvariant() {
        #expect(CheckoutResult(status: .dismissed, checkoutId: nil) == CheckoutResult.dismissed)
        #expect(CheckoutResult(status: .dismissed, checkoutId: "chk_abc") == nil)
        #expect(CheckoutResult(status: .succeeded, checkoutId: nil) == nil)
        #expect(CheckoutResult(status: .succeeded, checkoutId: "bad") == nil)
        #expect(CheckoutResult(status: .expired, checkoutId: "chk_abc") != nil)
        #expect(CheckoutResult.dismissed.checkoutId == nil)
    }
}

@Suite("PaymentsLkValidation")
struct ValidationTests {

    @Test("allowed checkout URLs", arguments: [
        "https://payments.lk/checkout/chk_abc123",
        "HTTPS://payments.lk/checkout/chk_abc123",
        "https://checkout.example.com:8443/c?x=1",
        "http://localhost:3000/checkout/chk_abc",
        "http://LOCALHOST/checkout/chk_abc",
        "http://127.0.0.1:4000/checkout/chk_abc",
    ])
    func allowedCheckoutURLs(url: String) throws {
        #expect(PaymentsLkValidation.isAllowedCheckoutURL(try makeURL(url)))
    }

    @Test("rejected checkout URLs", arguments: [
        "http://payments.lk/checkout/chk_abc",
        "http://192.168.1.10:3000/checkout",
        "http://localhost.evil.com/checkout",
        "http://127.0.0.2/checkout",
        "http://[::1]/checkout",
        "https://user@payments.lk/checkout",
        "https://user:pass@payments.lk/checkout",
        "https://:pass@payments.lk/checkout",
        "http://user:pass@localhost/checkout",
        "ftp://payments.lk/checkout",
        "javascript:alert(1)",
        "data:text/html,hello",
        "file:///etc/hosts",
        "myshop://payments-lk/return",
        "https:///no-host",
        "/relative/path",
    ])
    func rejectedCheckoutURLs(url: String) throws {
        #expect(!PaymentsLkValidation.isAllowedCheckoutURL(try makeURL(url)))
    }

    @Test("file URL is rejected")
    func fileURLRejected() {
        #expect(!PaymentsLkValidation.isAllowedCheckoutURL(URL(fileURLWithPath: "/tmp/checkout.html")))
    }

    @Test("valid callback schemes", arguments: [
        "myshop", "abc", "com.example.shop", "my-shop", "shop+pay", "a12", String(repeating: "a", count: 40),
    ])
    func validCallbackSchemes(scheme: String) {
        #expect(PaymentsLkValidation.isValidCallbackScheme(scheme))
    }

    @Test("invalid callback schemes", arguments: [
        "",
        "a",
        "ab",
        "MyShop",
        "1shop",
        "-shop",
        ".shop",
        "my_shop",
        "my shop",
        "myshop://",
        "myshop:",
        String(repeating: "a", count: 41),
        "http",
        "https",
        "file",
        "javascript",
        "data",
        "about",
        "\u{0441}hop",
    ])
    func invalidCallbackSchemes(scheme: String) {
        #expect(!PaymentsLkValidation.isValidCallbackScheme(scheme))
    }

    @Test("checkout id validation")
    func checkoutIdValidation() {
        #expect(PaymentsLkValidation.isValidCheckoutId("chk_a"))
        #expect(PaymentsLkValidation.isValidCheckoutId("chk_" + String(repeating: "9", count: 64)))
        #expect(!PaymentsLkValidation.isValidCheckoutId("chk_" + String(repeating: "9", count: 65)))
        #expect(!PaymentsLkValidation.isValidCheckoutId("chk_\u{0430}bc"))
    }
}
