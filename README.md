# PayByWallet for Flutter

Accept merchant payments — by QR code or merchant ID — from inside your Flutter
app, powered by the native TerraPay PayByWallet SDKs.

```text
                 Your Flutter app
                         │
                 paybywallet_flutter
                         │
              ┌──────────┴──────────┐
         iOS bridge            Android bridge
              │                     │
    TerraPayWalletClient        TerraPayClient
  (TerraPayWalletSDK.xcframework)  (payByWallet .aar)
```

Both native SDKs are bundled in this package. You add one dependency — there are
no frameworks to embed, no `.aar` to copy and no ProGuard rules to write.

---

## 1. Install

```yaml
# pubspec.yaml
dependencies:
  paybywallet_flutter:
    git:
      url: https://github.com/sdk-terrapay/paybywallet-flutter.git
      ref: v1.0.0
```

```sh
flutter pub get
```

Always pin `ref` to a release tag. Pub caches by ref, so tracking a branch would
give your developers and your CI different code with nothing in
`pubspec.lock` to show for it.

> If you were given credentials to access this repository, configure git before
> running `flutter pub get` — it shells out to `git clone` and cannot prompt you.
> See [Private repository access](#appendix-private-repository-access).

**App size impact** — roughly **+13.5 MB** on Android (arm64 release) and
**+2.9 MB** on iOS. Most of the Android figure is the bundled QR-detection
model, which is required for scanning to work on devices without Google Play
Services.

---

## 2. Platform setup

### Android

**Your `MainActivity` must extend `FlutterFragmentActivity`.** The SDK's UI is
Compose-based and requires an `androidx.activity.ComponentActivity`. Flutter's
default `FlutterActivity` extends plain `android.app.Activity`, so without this
change the first `launch()` call fails with `INVALID_CONTEXT`.

```kotlin
// android/app/src/main/kotlin/<your>/<package>/MainActivity.kt
package com.example.yourapp

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

```kotlin
// android/app/build.gradle.kts
android {
    compileSdk = 36

    defaultConfig {
        minSdk = 28          // required by the SDK
        targetSdk = 36
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
```

Build with **JDK 17**. Permissions (internet, camera, NFC) and the R8 keep-rules
are contributed by this package automatically.

### iOS

Set the deployment target to **15.0** in `ios/Podfile`:

```ruby
platform :ios, '15.0'
```

Add the camera usage string to `ios/Runner/Info.plist` — the app is rejected at
review, and crashes at runtime, without it:

```xml
<key>NSCameraUsageDescription</key>
<string>This allows the app to scan merchant QR codes.</string>
```

**On iOS 26 and later** your app must declare a scene manifest, which Flutter's
template does not yet generate. Without it the app launches to a blank white
screen and is terminated, with no Dart output to explain why. Add to
`Info.plist`:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key><string>UIWindowScene</string>
                <key>UISceneDelegateClassName</key><string>FlutterSceneDelegate</string>
                <key>UISceneConfigurationName</key><string>flutter</string>
                <key>UISceneStoryboardFile</key><string>Main</string>
            </dict>
        </array>
    </dict>
</dict>
```

---

## 3. Get an access token

The SDK is authenticated with an OAuth2 token pair that **your backend**
obtains. Do not ship the gateway credentials inside your app — anything
compiled into an APK or IPA can be extracted.

```
GET {base-url}/eig/getToken?subscriberid=%2B254712345678
user: <supplied by TerraPay>
password: <supplied by TerraPay>
```

```json
{
  "status": "OK",
  "subStatus": "Success",
  "access_token": "eyJhbGciOi…",
  "refresh_token": "eyJhbGciOi…",
  "expiry": "300"
}
```

Two details that commonly cause failures:

- `subscriberid` is the **dial code plus MSISDN** (`+254712345678`), and the
  leading `+` must be percent-encoded as `%2B`. Sent raw it arrives as a space
  and the lookup fails.
- `expiry` is returned as a **string** (`"300"`, seconds), not a number. Parsing
  it straight into an `int` throws.

Refresh before expiry to keep long sessions alive.

### Reference implementation

In production this call belongs on your server, and your app fetches the token
pair from your own API. The Dart below is the same request, useful for a
prototype or to check your credentials end to end:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class TokenPair {
  const TokenPair(this.accessToken, this.refreshToken, this.expiresIn);
  final String accessToken;
  final String refreshToken;
  final Duration expiresIn;
}

Future<TokenPair> fetchToken({
  required String baseUrl,       // see "Choose an environment" below
  required String user,          // supplied by TerraPay
  required String password,      // supplied by TerraPay
  required String dialCode,      // '+254'
  required String msisdn,        // '712345678'
}) async {
  // `replace(queryParameters:)` percent-encodes the leading '+' as %2B.
  // Interpolating it straight into the URL string does not, and the
  // gateway then receives a space.
  final uri = Uri.parse('$baseUrl/eig/getToken')
      .replace(queryParameters: {'subscriberid': '$dialCode$msisdn'});

  final response = await http.get(uri, headers: {
    'user': user,
    'password': password,
    'Accept': 'application/json',
  }).timeout(const Duration(seconds: 30));

  if (response.statusCode != 200) {
    throw Exception('Token request failed: HTTP ${response.statusCode}');
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final accessToken = body['access_token'] as String? ?? '';
  if (accessToken.isEmpty) {
    throw Exception('Token rejected: ${body['subStatus'] ?? body['status']}');
  }

  // `expiry` arrives as a String, so coerce rather than cast.
  final rawExpiry = body['expiry'];
  final seconds = rawExpiry is int ? rawExpiry : int.tryParse('$rawExpiry') ?? 300;

  return TokenPair(
    accessToken,
    body['refresh_token'] as String? ?? '',
    Duration(seconds: seconds),
  );
}
```

Requires `http: ^1.6.0` in your `pubspec.yaml`.

---

## 4. Choose an environment

| Environment | Token endpoint (`baseUrl`) |
| --- | --- |
| UAT / sandbox | `https://uat-connect.terrapay.com:27211` |
| Production | `https://api-payments.terrapay.com:27211` |

Production requires separate credentials — your UAT `user` / `password` pair
will not authenticate against it.

The same `baseUrl` serves `getToken`; the SDK reaches its own endpoints
internally.

**iOS** switches at runtime through the config:

```dart
PayByWalletConfig(
  // ...
  environment: PayByWalletEnvironment.production,   // default: sandbox
)
```

**Android ignores this field.** The endpoint is compiled into the bundled
native SDK, and the build shipped in this package targets **UAT**. Going live on
Android therefore needs a production build of the package from TerraPay — it is
not a code change on your side. Plan for it: an app that works against UAT on
both platforms will still hit UAT on Android after you flip `environment` to
`production`, with no error to indicate it.

Request production credentials and a production build from
sdk-support@terrapay.com before your go-live date.

> The app-side `baseUrl` above is only used for `getToken`. In production that
> call belongs on your server, so the URL and the credentials never reach the
> handset.

---

## 5. Launch the SDK

```dart
import 'package:paybywallet_flutter/paybywallet_flutter.dart';

final sdk = PayByWalletSdk.instance;

await sdk.launch(PayByWalletConfig(
  accessToken: token.accessToken,
  refreshToken: token.refreshToken,
  subscriberDialCode: '+254',
  subscriberCountry: 'KE',
  subscriberCountryName: 'Kenya',
  subscriberName: 'Jane Wanjiru',
  subscriberMsisdn: '712345678',
  subscriberCurrency: 'KES',
  walletBalance: 9999654.50,
  primaryColor: '52B44A',     // your brand colour
  secondaryColor: 'FFFFFF',
));
```

`launch()` validates the configuration natively and throws a
`PlatformException` if it is rejected, so you can `await` it and show the error
immediately rather than waiting for a callback.

### Configuration reference

| Parameter | Required | Rule |
| --- | --- | --- |
| `accessToken` | yes | from `getToken` |
| `refreshToken` | yes | from `getToken` |
| `subscriberDialCode` | yes | matches `^\+\d+$`, e.g. `+254` |
| `subscriberMsisdn` | yes | digits only, no dial code; length validated per country |
| `subscriberName` | yes | non-empty |
| `subscriberCountry` | yes | ISO 3166-1 alpha-2, e.g. `KE` |
| `subscriberCountryName` | yes | non-empty, e.g. `Kenya` |
| `subscriberCurrency` | yes | ISO 4217, e.g. `KES` |
| `walletBalance` | yes | number |
| `primaryColor` | yes | 6-digit hex, no `#`, e.g. `52B44A` |
| `secondaryColor` | yes | 6-digit hex, no `#`, e.g. `FFFFFF` |
| `referenceNumber` | no | your own reference. **Android only** |
| `environment` | no | `sandbox` (default) or `production`. **iOS only** — on Android the endpoint is fixed in the bundled SDK build |

---

## 6. Handle the result

Subscribe before calling `launch()`. Events arrive as a typed stream:

```dart
late final StreamSubscription<PayByWalletEvent> _sub;

@override
void initState() {
  super.initState();
  _sub = sdk.events.listen((event) async {
    switch (event) {
      case PinAuthenticateEvent(:final merchant):
        // The SDK has handed control back to you. Authenticate the user with
        // your own PIN / biometric screen, then confirm the payment.
        final ok = await showMyPinScreen(merchant);
        if (ok) await sdk.processPayment(generateOrderId());

      case PaymentSuccessEvent(:final result):
        showReceipt(result);

      case PaymentFailureEvent(:final result):
        showFailure(result);

      case SdkErrorEvent(:final code, :final message):
        showError('$code: $message');

      case SdkCancelledEvent():
        // user backed out
        break;

      case SdkClosedEvent():
        // iOS only: SDK UI dismissed with no terminal payment state
        break;
    }
  });
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

### The PIN step

**The SDK never collects the user's PIN.** When the user confirms an amount it
raises `PinAuthenticateEvent` with the merchant details and returns control to
your app. You authenticate the user however your wallet normally does, then call:

```dart
await sdk.processPayment(orderId);
```

`orderId` must be **unique per transaction** and alphanumeric, e.g.
`TXN` followed by 12 digits. Reusing an id will cause the payment to be
rejected.

`MerchantDetails` gives you `merchantName`, `amount` and `currency` so you can
show what is being paid on your own confirmation screen.

---

## 7. Error codes

`SdkErrorEvent.code`, and the `code` on a thrown `PlatformException`:

| Code | Meaning |
| --- | --- |
| `INVALID_CONTEXT` | `MainActivity` does not extend `FlutterFragmentActivity` (see §2) |
| `INVALID_DIAL_CODE` | `subscriberDialCode` is not `+` followed by digits |
| `INVALID_MSISDN` | MSISDN empty, non-numeric, or wrong length for the country |
| `INVALID_NAME` | `subscriberName` is empty |
| `INVALID_COUNTRY_CODE` | not a valid ISO 3166-1 alpha-2 code |
| `INVALID_COUNTRY_NAME` | `subscriberCountryName` is empty |
| `INVALID_CURRENCY` | not a valid ISO 4217 code |
| `INVALID_WALLET_BALANCE` | balance missing or not a number |
| `INVALID_PRIMARY_COLOR` | not a 6-digit hex value |
| `INVALID_SECONDARY_COLOR` | not a 6-digit hex value |
| `INVALID_TRANSACTION_ID` | `processPayment` called with an empty order id |
| `NETWORK_ERROR` | the device could not reach the gateway |
| `SDK_CLOSED` | the SDK flow was closed before completing |

---

## 8. Troubleshooting

| Symptom | Cause |
| --- | --- |
| `INVALID_CONTEXT` on first launch | `MainActivity` still extends `FlutterActivity`. See §2. |
| `MissingPluginException … com.terrapay.paybywallet/sdk` | Full restart needed after adding the dependency — hot reload does not register plugins. |
| App installs but shows a blank white screen on iOS 26+ | Missing `UIApplicationSceneManifest`. See §2. |
| Camera preview is black, or the app crashes when scanning | `NSCameraUsageDescription` missing, or camera permission denied in system settings. |
| Release build works but payments silently fail | Custom ProGuard rules are stripping the SDK. This package ships the required keep-rules; do not exclude them. |
| `flutter pub get` fails with `Repository not found` | Git credentials not configured. See the appendix. |
| Gradle fails with a bare version number | Wrong JDK. Build with JDK 17. |

---

## Appendix: private repository access

Only applies while this repository is private. `flutter pub get` cannot prompt
for credentials, so git must authenticate without interaction.

**Developers** — store your token once:

```sh
git config --global credential.helper osxkeychain      # macOS
git clone https://github.com/sdk-terrapay/paybywallet-flutter.git /tmp/auth-test
# username: your GitHub username;  password: your access token
rm -rf /tmp/auth-test
```

**CI** — inject the token without committing it anywhere:

```sh
git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf "https://github.com/"
```

Never put the token in the `url:` in `pubspec.yaml` — that commits a live
credential into your repository.

---

## Requirements summary

| | |
| --- | --- |
| Flutter | 3.3.0+ |
| Dart | 3.9+ |
| Android | minSdk 28, compileSdk 36, JDK 17, `FlutterFragmentActivity` |
| iOS | 15.0+, camera usage string, scene manifest on iOS 26+ |

## Support

sdk-support@terrapay.com

## License

Proprietary. See [LICENSE](LICENSE).
