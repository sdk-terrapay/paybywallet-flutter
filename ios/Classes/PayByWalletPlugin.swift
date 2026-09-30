import Flutter
import TerraPayWalletSDK
import UIKit

/// iOS half of the PayByWallet bridge.
///
/// Dart calls `launch` / `processPayment` down; the SDK's completion handler
/// callbacks are forwarded back up the same channel on the main thread.
public class PayByWalletPlugin: NSObject, FlutterPlugin {

  private static let channelName = "com.terrapay.paybywallet/sdk"

  private let channel: FlutterMethodChannel

  // MARK: - Silent-dismissal watch
  //
  // Some SDK exits (e.g. the back arrow on the QR scanner) dismiss its screens
  // without calling the completion handler. While a result is pending we watch
  // the presenting controller and report `onClosed` once the SDK's screen is
  // gone and no callback followed, so Dart is never left waiting.

  private var awaitingResult = false
  private var sawSdkScreen = false
  private weak var sdkPresenter: UIViewController?
  private var dismissalWatch: Timer?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = PayByWalletPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  // MARK: - Host view controller
  //
  // Resolved lazily rather than captured at registration: under
  // UIApplicationSceneManifest (mandatory on iOS 26+ SDKs) the window and its
  // root FlutterViewController do not exist yet when plugins are registered.

  private var hostController: UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window =
      scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
      ?? scenes.first?.keyWindow
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  // MARK: - Dart -> native

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "launch":
      launch(call, result: result)
    case "processPayment":
      processPayment(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func launch(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(Self.error("INVALID_ARGUMENTS", "Expected a configuration map."))
      return
    }
    guard let controller = hostController else {
      result(Self.error("INVALID_CONTEXT", "No visible view controller to present from."))
      return
    }

    // The iOS SDK takes the balance as a string; Dart sends a number.
    let walletBalance: String?
    switch args["walletBalance"] {
    case let value as NSNumber: walletBalance = value.stringValue
    case let value as String: walletBalance = value
    default: walletBalance = nil
    }

    let environment: TPEnvironment =
      (args["environment"] as? String) == "production" ? .production : .sandbox

    let config = TerraPayWalletSDKConfig(
      controller: controller,
      accessToken: args["accessToken"] as? String ?? "",
      refreshToken: args["refreshToken"] as? String ?? "",
      subscriberDialCode: args["subscriberDialCode"] as? String ?? "",
      subscriberCountry: args["subscriberCountry"] as? String ?? "",
      subscriberCountryName: args["subscriberCountryName"] as? String ?? "",
      subscriberName: args["subscriberName"] as? String ?? "",
      subscriberMSISDN: args["subscriberMSISDN"] as? String ?? "",
      subscriberCurrency: args["subscriberCurrency"] as? String ?? "",
      walletBalance: walletBalance,
      primaryColor: args["primaryColor"] as? String ?? "",
      secondaryColor: args["secondaryColor"] as? String ?? "",
      environment: environment
    )

    watchForSilentDismissal(from: controller)
    TerraPayWalletClient.shared.launch(with: config) { [weak self] type, error, merchant, status in
      self?.forward(type: type, error: error, merchant: merchant, status: status)
    }
    result(nil)
  }

  private func processPayment(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let transactionId = args["transactionId"] as? String,
      !transactionId.isEmpty
    else {
      result(Self.error("INVALID_TRANSACTION_ID", "transactionId is required."))
      return
    }
    let controller = hostController
    watchForSilentDismissal(from: controller)
    TerraPayWalletClient.shared.processPayment(
      controller: controller,
      transactionId: transactionId
    )
    result(nil)
  }

  private func watchForSilentDismissal(from presenter: UIViewController?) {
    stopWatching()
    awaitingResult = true
    sawSdkScreen = false
    sdkPresenter = presenter
    // The SDK presents asynchronously, so poll rather than check once.
    dismissalWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.checkForSilentDismissal()
    }
  }

  private func checkForSilentDismissal() {
    guard awaitingResult, let presenter = sdkPresenter else {
      stopWatching()
      return
    }
    if presenter.presentedViewController != nil {
      sawSdkScreen = true
      return
    }
    guard sawSdkScreen else { return }

    // The SDK's own exit callbacks fire from the dismissal's completion block,
    // so give them a moment before deciding none is coming.
    stopWatching()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self, self.awaitingResult else { return }
      self.send("onClosed", [:])
    }
  }

  private func stopWatching() {
    dismissalWatch?.invalidate()
    dismissalWatch = nil
  }

  // MARK: - Native -> Dart

  private func forward(
    type: TPLaunchType,
    error: TPErrorInfo?,
    merchant: TPMerchant?,
    status: TPPaymentStatus?
  ) {
    switch type {
    case .onPINAuthenticate:
      send("onPinAuthenticate", [
        "merchantName": merchant?.merchantName as Any,
        "subscriberAmount": merchant?.subscriberAmount as Any,
        "subscriberCurrency": merchant?.subscriberCurrency as Any,
      ])
    case .onPaymentSuccess:
      send("onPaymentSuccess", Self.paymentStatusMap(status, error: error))
    case .onPaymentFailure:
      send("onPaymentFailure", Self.paymentStatusMap(status, error: error))
    case .onError:
      send("onError", [
        "code": error?.code ?? "",
        "message": error?.message ?? "Something went wrong.",
      ])
    case .cancelled:
      send("onCancelled", [
        "code": error?.code ?? "",
        "message": error?.message ?? "User cancelled.",
      ])
    case .closed:
      send("onClosed", [:])
    @unknown default:
      send("onError", ["code": "", "message": "Unrecognised SDK result."])
    }
  }

  /// Same keys as the Android bridge's `TPPaymentStatus.toMap()`. Falls back to
  /// the error info when the SDK reports a failure without a status.
  private static func paymentStatusMap(
    _ status: TPPaymentStatus?,
    error: TPErrorInfo?
  ) -> [String: Any] {
    let responseStatus: String? = status?.responseStatus ?? error?.code
    let responseMessage: String? = status?.responseMessage ?? error?.message
    return [
      "responseStatus": responseStatus as Any,
      "responseMessage": responseMessage as Any,
      "gatewayReferenceId": status?.gatewayReferenceId as Any,
      "orderId": status?.orderId as Any,
    ]
  }

  private func send(_ method: String, _ arguments: [String: Any]) {
    // Any callback ends the wait for this launch / processPayment.
    awaitingResult = false
    stopWatching()
    // Strip NSNull so optional fields arrive as Dart nulls.
    let cleaned = arguments.filter { !($0.value is NSNull) }
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod(method, arguments: cleaned)
    }
  }

  private static func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
