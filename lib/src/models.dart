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
    required this.primaryColor,
    required this.secondaryColor,
    this.environment = PayByWalletEnvironment.sandbox,
    this.walletBalance,
    this.merchantCountry,
    this.merchantAcquirer,
    this.transactionMinLimit,
    this.transactionMaxLimit,
  });

  final String accessToken;
  final String refreshToken;
  final String subscriberDialCode;
  final String subscriberCountry;
  final String subscriberCountryName;
  final String subscriberName;
  final String subscriberMsisdn;
  final String subscriberCurrency;

  /// 6-digit hex, no leading '#', e.g. `52B44A`.
  final String primaryColor;

  /// 6-digit hex, no leading '#', e.g. `FFFFFF`.
  final String secondaryColor;

  /// See [PayByWalletEnvironment]. Defaults to sandbox.
  final PayByWalletEnvironment environment;

  /// Optional; omit to leave the balance unset.
  final double? walletBalance;

  /// Merchant's country selected by the user, ISO 3166-1 alpha-2 (e.g. `KE`).
  final String? merchantCountry;

  /// PSP ID of the merchant's provider selected by the user (e.g. `25403`).
  final String? merchantAcquirer;

  /// Minimum amount allowed per transaction, in the merchant's currency.
  final double? transactionMinLimit;

  /// Maximum amount allowed per transaction, in the merchant's currency.
  final double? transactionMaxLimit;

  Map<String, dynamic> toMap() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'subscriberDialCode': subscriberDialCode,
    'subscriberCountry': subscriberCountry,
    'subscriberCountryName': subscriberCountryName,
    'subscriberName': subscriberName,
    'subscriberMSISDN': subscriberMsisdn,
    'subscriberCurrency': subscriberCurrency,
    'primaryColor': primaryColor,
    'secondaryColor': secondaryColor,
    'environment': environment.name,
    if (walletBalance != null) 'walletBalance': walletBalance,
    if (merchantCountry != null) 'merchantCountry': merchantCountry,
    if (merchantAcquirer != null) 'merchantAcquirer': merchantAcquirer,
    if (transactionMinLimit != null) 'transactionMinLimit': transactionMinLimit,
    if (transactionMaxLimit != null) 'transactionMaxLimit': transactionMaxLimit,
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

/// Outcome of a completed payment attempt, mirroring the native SDKs'
/// `TPPaymentStatus` (same fields on both platforms).
class PaymentResult {
  const PaymentResult({
    this.responseStatus,
    this.responseMessage,
    this.gatewayReferenceId,
    this.orderId,
    this.merchantId,
    this.merchantName,
    this.merchantAmount,
    this.merchantCurrency,
    this.subscriberAmount,
    this.subscriberCurrency,
  });

  final String? responseStatus;
  final String? responseMessage;
  final String? gatewayReferenceId;
  final String? orderId;
  final String? merchantId;
  final String? merchantName;

  /// Amount credited to the merchant, in [merchantCurrency].
  final String? merchantAmount;
  final String? merchantCurrency;

  /// Amount debited from the subscriber, in [subscriberCurrency].
  final String? subscriberAmount;
  final String? subscriberCurrency;

  factory PaymentResult.fromMap(Map<dynamic, dynamic> map) => PaymentResult(
    responseStatus: map['responseStatus'] as String?,
    responseMessage: map['responseMessage'] as String?,
    gatewayReferenceId: map['gatewayReferenceId'] as String?,
    orderId: map['orderId'] as String?,
    merchantId: map['merchantId'] as String?,
    merchantName: map['merchantName'] as String?,
    merchantAmount: map['merchantAmount'] as String?,
    merchantCurrency: map['merchantCurrency'] as String?,
    subscriberAmount: map['subscriberAmount'] as String?,
    subscriberCurrency: map['subscriberCurrency'] as String?,
  );

  @override
  String toString() {
    return [
      if (responseMessage != null) responseMessage,
      if (responseStatus != null) 'status: $responseStatus',
      if (orderId != null) 'order: $orderId',
      if (gatewayReferenceId != null) 'ref: $gatewayReferenceId',
      if (merchantName != null) 'merchant: $merchantName',
      if (merchantAmount != null)
        'merchant amount: ${merchantCurrency ?? ''} $merchantAmount'.trim(),
      if (subscriberAmount != null)
        'paid: ${subscriberCurrency ?? ''} $subscriberAmount'.trim(),
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

/// The SDK UI was dismissed without a terminal payment state.
class SdkClosedEvent extends PayByWalletEvent {
  const SdkClosedEvent();
}
