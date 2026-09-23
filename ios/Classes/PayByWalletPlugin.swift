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
    TerraPayWalletClient.shared.processPayment(
      controller: hostController,
      transactionId: transactionId
    )
    result(nil)
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
      send("onPaymentSuccess", ["raw": status?.description as Any])
    case .onPaymentFailure:
      send("onPaymentFailure", [
        "raw": status?.description as Any,
        "responseCode": error?.code as Any,
        "responseMessage": error?.message as Any,
      ])
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

  private func send(_ method: String, _ arguments: [String: Any]) {
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
