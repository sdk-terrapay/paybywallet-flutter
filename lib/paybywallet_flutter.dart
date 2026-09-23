/// Flutter bindings for the TerraPay PayByWallet SDKs.
///
/// A single method channel fronts both native SDKs:
///
/// ```text
///                Flutter (this package)
///                         |
///              +----------+----------+
///              |                     |
///        iOS bridge            Android bridge
///              |                     |
///   TerraPayWalletClient        TerraPayClient
///   (TerraPayWalletSDK)         (payByWallet .aar)
/// ```
///
/// Usage:
///
/// ```dart
/// final sdk = PayByWalletSdk.instance;
/// sdk.events.listen((event) { /* handle PIN / success / failure */ });
/// await sdk.launch(PayByWalletConfig(accessToken: ..., refreshToken: ..., ...));
/// ```
///
/// Your app fetches the OAuth2 token pair (`GET /eig/getToken`) and passes it
/// in; this package deliberately does not talk to the gateway itself.
library;

export 'src/models.dart';
export 'src/paybywallet_sdk.dart';
