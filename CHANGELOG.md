## 1.0.1

* Documentation only, no code change. README rewritten as an integration guide:
  a working `fetchToken` reference implementation, UAT and production endpoints,
  error-code and troubleshooting tables.
* Removed the private-repository access notes now that the package is public.

## 1.0.0

* Initial release: `launch` / `processPayment` bridged to the native TerraPay
  PayByWallet SDKs, with SDK callbacks exposed as a `Stream<PayByWalletEvent>`.
* Bundles `payByWallet-release.aar` (Android) and `TerraPayWalletSDK.xcframework` (iOS).
* Ships `consumer-rules.pro` so embedding apps need no R8 configuration.
