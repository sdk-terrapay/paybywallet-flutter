## 1.0.0

* Initial release: `launch` / `processPayment` bridged to the native TerraPay
  PayByWallet SDKs, with SDK callbacks exposed as a `Stream<PayByWalletEvent>`.
* `PayByWalletConfig.environment` selects the sandbox or production backend at
  runtime on both platforms; an unrecognised environment is rejected rather
  than falling back to sandbox.
* Payment results are delivered as `PaymentResult`, mirroring the native SDKs'
  `TPPaymentStatus`: `responseStatus`, `responseMessage`,
  `gatewayReferenceId`, `orderId` -- the same fields on Android and iOS.
* Bundles `payByWallet-release.aar` (Android) and `TerraPayWalletSDK.xcframework` (iOS).
* Ships `consumer-rules.pro` so embedding apps need no R8 configuration.
