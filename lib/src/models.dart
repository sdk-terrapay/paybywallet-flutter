/// Which TerraPay backend the SDK talks to. Honoured on both platforms.
enum PayByWalletEnvironment { sandbox, production }

/// Configuration handed to the native TerraPay PayByWallet SDK on launch.
class PayByWalletConfig {
  const PayByWalletConfig({
    required this.accessToken,
    required this.refreshToken,
    required this.subscriberDialCode,
    required this.subscriberCountry,
    required this.subscriberCountryName,
    required this.subscriberName,
    required this.subscriberMsisdn,
    required this.subscriberCurrency,
    required this.walletBalance,
    required this.primaryColor,
    required this.secondaryColor,
    this.referenceNumber,
    this.environment = PayByWalletEnvironment.sandbox,
  });

  final String accessToken;
  final String refreshToken;
  final String subscriberDialCode;
  final String subscriberCountry;
  final String subscriberCountryName;
  final String subscriberName;
  final String subscriberMsisdn;
  final String subscriberCurrency;
  final double walletBalance;

  /// 6-digit hex, no leading '#', e.g. `52B44A`.
  final String primaryColor;

  /// 6-digit hex, no leading '#', e.g. `FFFFFF`.
  final String secondaryColor;

  /// Android-only optional reference passed through to `TerraPayClient.init`.
  final String? referenceNumber;

  /// See [PayByWalletEnvironment]. Defaults to sandbox.
  final PayByWalletEnvironment environment;

  Map<String, dynamic> toMap() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'subscriberDialCode': subscriberDialCode,
        'subscriberCountry': subscriberCountry,
        'subscriberCountryName': subscriberCountryName,
        'subscriberName': subscriberName,
        'subscriberMSISDN': subscriberMsisdn,
        'subscriberCurrency': subscriberCurrency,
        'walletBalance': walletBalance,
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'referenceNumber': referenceNumber,
        'environment': environment.name,
      };
}

/// Merchant the user is about to pay, delivered with [PinAuthenticateEvent].
class MerchantDetails {
  const MerchantDetails({this.merchantName, this.amount, this.currency});

  final String? merchantName;
  final String? amount;
  final String? currency;

  factory MerchantDetails.fromMap(Map<dynamic, dynamic> map) => MerchantDetails(
        merchantName: map['merchantName'] as String?,
        amount: map['subscriberAmount'] as String?,
        currency: map['subscriberCurrency'] as String?,
      );

  @override
  String toString() => '$merchantName - $currency $amount';
}

/// Outcome of a completed payment attempt.
class PaymentResult {
  const PaymentResult({
    this.responseCode,
    this.responseMessage,
    this.gatewayReferenceId,
    this.orderId,
    this.raw,
  });

  final String? responseCode;
  final String? responseMessage;
  final String? gatewayReferenceId;
  final String? orderId;

  /// iOS returns a single opaque description string rather than fields.
  final String? raw;

  factory PaymentResult.fromMap(Map<dynamic, dynamic> map) => PaymentResult(
        responseCode: map['responseCode'] as String?,
        responseMessage: map['responseMessage'] as String?,
        gatewayReferenceId: map['gatewayReferenceId'] as String?,
        orderId: map['orderId'] as String?,
        raw: map['raw'] as String?,
      );

  @override
  String toString() {
    if (raw != null && raw!.isNotEmpty) return raw!;
    return [
      if (responseMessage != null) responseMessage,
      if (responseCode != null) 'code: $responseCode',
      if (orderId != null) 'order: $orderId',
      if (gatewayReferenceId != null) 'ref: $gatewayReferenceId',
    ].whereType<String>().join(' • ');
  }
}

/// Events pushed up from the native SDK.
sealed class PayByWalletEvent {
  const PayByWalletEvent();
}

/// The SDK needs the host app to authenticate the user before charging them.
/// Show your own PIN screen, then call `processPayment` with a fresh order id.
class PinAuthenticateEvent extends PayByWalletEvent {
  const PinAuthenticateEvent(this.merchant);
  final MerchantDetails merchant;
}

class PaymentSuccessEvent extends PayByWalletEvent {
  const PaymentSuccessEvent(this.result);
  final PaymentResult result;
}

class PaymentFailureEvent extends PayByWalletEvent {
  const PaymentFailureEvent(this.result);
  final PaymentResult result;
}

class SdkErrorEvent extends PayByWalletEvent {
  const SdkErrorEvent(this.code, this.message);
  final String code;
  final String message;
}

class SdkCancelledEvent extends PayByWalletEvent {
  const SdkCancelledEvent(this.code, this.message);
  final String code;
  final String message;
}

/// iOS-only: the SDK UI was dismissed without a terminal payment state.
class SdkClosedEvent extends PayByWalletEvent {
  const SdkClosedEvent();
}
