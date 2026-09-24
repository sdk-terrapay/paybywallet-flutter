## 1.0.1

* Android: `PayByWalletConfig.environment` now selects the backend at runtime,
  as on iOS. The bundled `payByWallet-release.aar` compiles in both the UAT and
  production endpoints; an unrecognised environment is rejected rather than
  falling back to sandbox.

## 1.0.0

* Initial release: `launch` / `processPayment` bridged to the native TerraPay
  PayByWallet SDKs, with SDK callbacks exposed as a `Stream<PayByWalletEvent>`.
* Bundles `payByWallet-release.aar` (Android) and `TerraPayWalletSDK.xcframework` (iOS).
* Ships `consumer-rules.pro` so embedding apps need no R8 configuration.
