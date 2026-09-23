## 1.0.0

* Initial release: `launch` / `processPayment` bridged to the native TerraPay
  PayByWallet SDKs, with SDK callbacks exposed as a `Stream<PayByWalletEvent>`.
* Bundles `payByWallet-release.aar` (Android) and `TerraPayWalletSDK.xcframework` (iOS).
* Ships `consumer-rules.pro` so embedding apps need no R8 configuration.
