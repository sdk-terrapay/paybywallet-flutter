import 'dart:async';

import 'package:flutter/services.dart';

import 'models.dart';

/// Flutter side of the platform channel that drives the native TerraPay
/// PayByWallet SDK (`TerraPayClient` on Android, `TerraPayWalletClient` on iOS).
///
/// Calls go down through [launch] / [processPayment]; the SDK's callbacks come
/// back up over the same channel and are re-published on [events].
class PayByWalletSdk {
  PayByWalletSdk._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final PayByWalletSdk instance = PayByWalletSdk._();

  static const MethodChannel _channel =
      MethodChannel('com.terrapay.paybywallet/sdk');

  final StreamController<PayByWalletEvent> _events =
      StreamController<PayByWalletEvent>.broadcast();

  /// Callbacks raised by the native SDK.
  Stream<PayByWalletEvent> get events => _events.stream;

  /// Validates [config] natively and presents the SDK's payment UI.
  ///
  /// Throws [PlatformException] if the SDK rejects the configuration.
  Future<void> launch(PayByWalletConfig config) {
    return _channel.invokeMethod<void>('launch', config.toMap());
  }

  /// Completes the payment after your own PIN screen has authenticated the
  /// user. [transactionId] must be a unique alphanumeric order id.
  Future<void> processPayment(String transactionId) {
    return _channel.invokeMethod<void>('processPayment', {
      'transactionId': transactionId,
    });
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'onPinAuthenticate':
        _events.add(PinAuthenticateEvent(MerchantDetails.fromMap(args)));
      case 'onPaymentSuccess':
        _events.add(PaymentSuccessEvent(PaymentResult.fromMap(args)));
      case 'onPaymentFailure':
        _events.add(PaymentFailureEvent(PaymentResult.fromMap(args)));
      case 'onError':
        _events.add(SdkErrorEvent(
          (args['code'] as String?) ?? '',
          (args['message'] as String?) ?? 'Something went wrong.',
        ));
      case 'onCancelled':
        _events.add(SdkCancelledEvent(
          (args['code'] as String?) ?? '',
          (args['message'] as String?) ?? 'User cancelled.',
        ));
      case 'onClosed':
        _events.add(const SdkClosedEvent());
      default:
        throw MissingPluginException(
          'Unhandled PayByWallet callback: ${call.method}',
        );
    }
    return null;
  }
}
