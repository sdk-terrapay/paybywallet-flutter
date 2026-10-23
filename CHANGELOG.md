## 1.1.0

* `PayByWalletConfig` gains optional `merchantCountry`, `merchantAcquirer`,
  `transactionMinLimit` and `transactionMaxLimit`, forwarded to both SDKs.
* `walletBalance` is now optional (`double?`); omit it to leave the balance
  unset.
* A provided `walletBalance` must be greater than zero. Android now rejects
  zero, negative or non-numeric balances with `ERR_INVALID_WALLET_BALANCE`
  (previously `INVALID_WALLET_BALANCE`), matching the iOS SDK.
* The plugin's own context check now reports `ERR_INVALID_CONTEXT`
  (previously `INVALID_CONTEXT`), matching the Android SDK's code.
* `processPayment` validation of the transaction id now comes from the native
  SDKs (`ERR_INVALID_TRANSACTION_ID`) instead of the plugin.
* `PaymentResult` gains `merchantId`, `merchantName`, `merchantAmount`,
  `merchantCurrency`, `subscriberAmount` and `subscriberCurrency`, from the
  native SDKs' `TPPaymentStatus` on both platforms.
* Bundles the updated `payByWallet-release.aar`, which adds the merchant and
  transaction-limit configuration, the extended `TPPaymentStatus`, and the
  new error codes. No new transitive dependencies.

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
