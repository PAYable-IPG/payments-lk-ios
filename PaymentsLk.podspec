# CocoaPods, for apps that have not moved to Swift Package Manager. The version
# is the newest in CHANGELOG.md, as for the Swift package, and the source is the
# same tag of github.com/PAYable-IPG/payments-lk-ios. CocoaPods' trunk stops
# taking new versions on 2 December 2026; Swift Package Manager is the way to
# install this after that.
Pod::Spec.new do |s|
  s.name = "PaymentsLk"
  s.version = "0.1.2"
  s.summary = "Open a Payments.lk hosted checkout from an iOS app."
  s.description = <<~DESC
    Opens a Payments.lk hosted checkout in ASWebAuthenticationSession, the system's
    own secure browser sheet, and answers the outcome from the checkout's return to
    your app's URL scheme. Card details are entered on the hosted page, never in
    your app, and your server confirms every payment.
  DESC
  s.homepage = "https://payments.lk/developers/sdks#ios"
  s.license = { :type => "MIT", :file => "LICENSE" }
  s.author = { "Payments.lk" => "hello@payments.lk" }
  s.source = { :git => "https://github.com/PAYable-IPG/payments-lk-ios.git", :tag => s.version.to_s }
  s.documentation_url = "https://payments.lk/developers/sdks#ios"

  s.swift_versions = ["5.9"]
  s.ios.deployment_target = "15.0"
  s.osx.deployment_target = "12.0"
  s.source_files = "Sources/PaymentsLk/**/*.swift"
  s.ios.frameworks = "AuthenticationServices", "UIKit"
  s.osx.frameworks = "AuthenticationServices", "AppKit"
end
