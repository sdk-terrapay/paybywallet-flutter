# paybywallet_flutter

Flutter bindings for the TerraPay PayByWallet SDKs — merchant payments by QR
code or merchant ID, on Android and iOS.

```text
                 Flutter (this package)
                          |
               +----------+----------+
               |                     |
         iOS bridge            Android bridge
               |                     |
    TerraPayWalletClient         TerraPayClient
   (TerraPayWalletSDK.xcframework)  (payByWallet .aar)
```

Both native SDKs are **bundled in this package** — apps add one dependency and
get the binaries, the transitive dependencies and the R8 keep-rules with no
further setup.

## Install

```yaml
dependencies:
  paybywallet_flutter:
    git:
      url: git@github.com:sdk-terrapay/paybywallet-flutter.git
      ref: v1.0.0
```

Then `flutter pub get`. Pin `ref` to a tag so builds are reproducible.

## Host app requirements

**Android — `MainActivity` must extend `FlutterFragmentActivity`.** The SDK's UI
is Compose-based and rejects any context that is not an
`androidx.activity.ComponentActivity`. Flutter's default `FlutterActivity`
extends plain `android.app.Activity`, so without this the first `launch()` fails
with `INVALID_CONTEXT`.

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

Your app's `minSdk` must be **28** or higher, and `compileSdk` **36**.

**iOS** needs `NSCameraUsageDescription` in `Info.plist` (QR scanning), a
deployment target of **15.0+**, and — on iOS 26+ SDKs — a
`UIApplicationSceneManifest`, which Flutter's template does not yet ship.

## Usage

Your app fetches the OAuth2 token pair; this package never talks to the gateway
itself.

```dart
import 'package:paybywallet_flutter/paybywallet_flutter.dart';

final sdk = PayByWalletSdk.instance;

sdk.events.listen((event) {
  switch (event) {
    case PinAuthenticateEvent(:final merchant):
      // Authenticate the user yourself, then confirm with a unique order id.
      sdk.processPayment('TXN123456789012');
    case PaymentSuccessEvent(:final result):  print('paid: $result');
    case PaymentFailureEvent(:final result):  print('failed: $result');
    case SdkErrorEvent(:final code, :final message): print('$code $message');
    case SdkCancelledEvent(): print('cancelled');
    case SdkClosedEvent():    print('closed');   // iOS only
  }
});

await sdk.launch(PayByWalletConfig(
  accessToken: token.accessToken,
  refreshToken: token.refreshToken,
  subscriberDialCode: '+254',
  subscriberCountry: 'KE',
  subscriberCountryName: 'Kenya',
  subscriberName: 'Giri Babu',
  subscriberMsisdn: '476864812',
  subscriberCurrency: 'KES',
  walletBalance: 9999654.50,
  primaryColor: '52B44A',
  secondaryColor: 'FFFFFF',
));
```

### The PIN step

The SDK does not collect the PIN. On `PinAuthenticateEvent` it returns the
merchant details and hands control back to your app, which authenticates the
user however it likes and then calls `processPayment` with a **unique**
alphanumeric order id.

### Environments

`PayByWalletConfig.environment` defaults to `sandbox` and is **iOS-only**. On
Android the base URL is compiled into the bundled `.aar` (currently a UAT
build), so switching to production there means swapping the `.aar`.

## Maintaining the bundled SDKs

* **Android** — `android/libs/payByWallet-release.aar`, exposed through a
  `flatDir` repository because AGP rejects direct local `.aar` file
  dependencies inside a library module. It carries no POM, so its transitive
  dependencies are pinned by hand in `android/build.gradle`; re-derive them with
  `jdeps -verbose:package` over the `.aar`'s `classes.jar` whenever it is
  refreshed.
* **`android/src/main/AndroidManifest.xml` merges a `NoActionBar` theme onto the
  SDK's `PaymentsHomeActivity`.** The SDK declares that activity with an
  `android:label` but no `android:theme`, so it falls back to the platform
  default, which has an ActionBar — rendering a stray bar showing the SDK's
  internal "PaymentsHome" label above the SDK's own header in every embedding
  app. Remove the override only if the SDK starts theming its own activity.
* **Do not swap ML Kit for the unbundled variant.** `barcode-scanning` bundles a
  ~4.7 MB detection model and is the single biggest contributor to app size, so
  `play-services-mlkit-barcode-scanning` looks like an easy ~6 MB saving. It is
  not: that variant loads the detector from Play Services, and on a handset
  without it the camera preview still runs while a framed QR is simply never
  detected — a silent failure, logged only as *"No acceptable module
  com.google.android.gms.vision.dynamite found"*. Verified broken on a Huawei
  device (2026-09-23). Non-GMS handsets are core devices for this SDK.
* **`android/consumer-rules.pro`** — the shipped `.aar` has no `proguard.txt`, so
  these rules are what stop R8 from obfuscating the SDK in embedding apps' release
  builds. Gson maps the SDK's DTOs by *field name* (none carry
  `@SerializedName`), so the model keep-rule must retain members verbatim.
* **iOS** — `ios/Frameworks/TerraPayWalletSDK.xcframework`, vendored by
  `ios/paybywallet_flutter.podspec`. The `dSYMs/` directories are **stripped**:
  Xcode discards them when packaging an app, so they cost ~13 MB in every clone
  and change nothing in the build. If you need to symbolicate a crash inside the
  SDK itself, take them from `SDK/iOS/build/TerraPayWalletSDK.xcframework`, and
  strip them again after refreshing the xcframework:

  ```sh
  rm -rf ios/Frameworks/TerraPayWalletSDK.xcframework/*/dSYMs
  ```

See `../paybywallet_sample` for a complete host app.

## License

Proprietary — see [LICENSE](LICENSE).
