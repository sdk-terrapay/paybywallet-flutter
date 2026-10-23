# 📦 TerraPay PayByWallet SDK for Flutter

This SDK, provided by TerraPay, enables seamless payment transactions between
customers and merchants through the partner mobile application. It supports
multiple payment methods, including QR code scanning and merchant ID–based
payments, and is designed for easy integration with Flutter applications on
Android and iOS.

## 🚀 Features

- QR Code and Merchant ID Payments.
- Customizable User Experience with brand colors.
- Launch SDK with a single entry point.
- Easily embeddable into any Flutter app.

## 📲 Requirements

- Flutter 3.3.0+ / Dart 3.9+
- **Android** — minSdk 28, compileSdk 36, JDK 17
- **iOS** — 15.0+, Xcode 15+

Adding the package increases app size by roughly **+13.5 MB** on Android
(arm64 release) and **+2.9 MB** on iOS. Most of the Android figure is the
bundled QR-detection model, required for scanning to work on devices without
Google Play Services.

## 🔧 Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  paybywallet_flutter:
    git:
      url: https://github.com/sdk-terrapay/paybywallet-flutter.git
      ref: v1.1.0
```

```sh
flutter pub get
```

Pin `ref` to a release tag. Pub caches by ref, so tracking a branch would give
your developers and your CI different code with nothing in `pubspec.lock` to
show for it.

The native Android and iOS SDKs ship inside the package — there are no
frameworks to embed, no `.aar` to copy and no ProGuard rules to add.

## 🛠️ Permissions and platform setup

### Android

Your `MainActivity` **must** extend `FlutterFragmentActivity`. The SDK's UI is
Compose-based and requires an `androidx.activity.ComponentActivity`; Flutter's
default `FlutterActivity` extends plain `android.app.Activity`, so without this
the first `launch()` fails with `INVALID_CONTEXT`.

```kotlin
// android/app/src/main/kotlin/<your>/<package>/MainActivity.kt
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

Internet, camera and NFC permissions, and the R8 keep-rules, are contributed by
the package automatically.

### iOS

Set the deployment target in `ios/Podfile`:

```ruby
platform :ios, '15.0'
```

`Info.plist` must contain `NSCameraUsageDescription` with a string explaining
how the app uses the camera — the app crashes at runtime and is rejected at
review without it:

```xml
<key>NSCameraUsageDescription</key>
<string>This will allow <your-app-name> to scan QR Code.</string>
```

**When building with Xcode 27 (iOS 27 SDK) or later** the app must also declare
a scene manifest, which Flutter's template does not yet generate. Without it the
app launches to a blank white screen and is terminated, with no Dart output to
explain why. The requirement follows the SDK the app is built with, not the iOS
version of the device, and the manifest is safe to add for older SDKs too:

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

## 🔐 Authentication (OAuth2)

The SDK requires OAuth2 authentication. Your application must obtain both an
**access token** and a **refresh token** before launching the SDK, and pass both
in during initialization.

**Token generation endpoint**

```
GET {base-url}/eig/getToken?subscriberid=%2B254712345678
user: <supplied by TerraPay>
password: <supplied by TerraPay>
```

**Sample response**

```json
{
  "status": "OK",
  "subStatus": "Success",
  "access_token": "eyJhbGciOiJIUzI1NiJ9…",
  "refresh_token": "eyJhbGciOiJIUzI1NiJ9…",
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

> Perform this call from **your backend** and have the app fetch the token pair
> from your own API. Credentials compiled into an app can be extracted from the
> APK or IPA.

### Reference implementation

The same request in Dart, useful for a prototype or to verify your credentials
end to end:

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
  required String baseUrl,       // see Environments below
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

## 🌍 Environments

| Environment | Token endpoint (`baseUrl`) |
| --- | --- |
| UAT / sandbox | `https://uat-connect.terrapay.com:27211` |
| Production | `https://api-payments.terrapay.com:27211` |

Production requires separate credentials — your UAT `user` / `password` pair
will not authenticate against it.

Both platforms switch at runtime through the config:

```dart
PayByWalletConfig(
  // ...
  environment: PayByWalletEnvironment.production,   // default: sandbox
)
```

Request production credentials from sdk-support@terrapay.com before your
go-live date.

## 🛠️ Usage

### Config params validation

| Parameter | Required | Validation rule |
| --- | --- | --- |
| `accessToken` | Yes | OAuth2 access token from your backend |
| `refreshToken` | Yes | OAuth2 refresh token from your backend |
| `subscriberDialCode` | Yes | Must match the pattern `^\+\d+$` |
| `subscriberMsisdn` | Yes | Digits only, no dial code; length validated per country |
| `subscriberName` | Yes | Must not be empty |
| `subscriberCountry` | Yes | Valid ISO 3166-1 alpha-2 country code |
| `subscriberCountryName` | Yes | Must not be empty |
| `subscriberCurrency` | Yes | Valid ISO 4217 currency code |
| `primaryColor` | Yes | Valid 6-digit hex code, no `#` (e.g. `EC1B24`) |
| `secondaryColor` | Yes | Valid 6-digit hex code, no `#` (e.g. `FFFFFF`) |
| `environment` | No | `sandbox` (default) or `production` |
| `walletBalance` | No | Numeric, greater than zero; omit to leave the balance unset |
| `merchantCountry` | No | Merchant's country selected by the user in the Mixx app; ISO 3166-1 alpha-2 (e.g. `KE`) |
| `merchantAcquirer` | No | PSP ID of the merchant's provider selected by the user in the Mixx app (e.g. `'25403'`); letters and digits only; requires `merchantCountry` |
| `transactionMinLimit` | No | Numeric, greater than zero; minimum amount allowed per transaction, in Merchant's Currency |
| `transactionMaxLimit` | No | Numeric, greater than zero and not less than `transactionMinLimit`; maximum amount allowed per transaction, in Merchant's Currency |

#### 1. Import the SDK

```dart
import 'package:paybywallet_flutter/paybywallet_flutter.dart';
```

#### 2. Initialize and launch the SDK

```dart
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
  primaryColor: '52B44A',
  secondaryColor: 'FFFFFF',
  // Optional
  environment: PayByWalletEnvironment.sandbox,
  walletBalance: 9999654.50,
  merchantCountry: 'KE',
  merchantAcquirer: '25403',
  transactionMinLimit: 1000.00,
  transactionMaxLimit: 5000000.00,
));
```

`launch()` validates the configuration natively. On Android a rejected
configuration throws a `PlatformException`, so you can `await` it and surface
the error immediately. On iOS the SDK reports it as an `SdkErrorEvent` on the
event stream instead, so handle both.

#### 3. Handle the SDK results

Subscribe before calling `launch()`. Callbacks arrive as a typed stream:

```dart
late final StreamSubscription<PayByWalletEvent> _sub;

@override
void initState() {
  super.initState();
  _sub = sdk.events.listen((event) async {
    switch (event) {
      case PinAuthenticateEvent(:final merchant):
        // PIN/OTP authentication is required. Open your own PIN screen,
        // validate the user, then confirm the payment.
        final ok = await showMyPinScreen(merchant);
        if (ok) await sdk.processPayment(generateOrderId());

      case PaymentSuccessEvent(:final result):
        showReceipt(result);          // transaction succeeded

      case PaymentFailureEvent(:final result):
        showFailure(result);          // transaction failed

      case SdkErrorEvent(:final code, :final message):
        showError('$code: $message'); // invalid parameters or SDK error

      case SdkCancelledEvent():
        break;                        // user cancelled the flow

      case SdkClosedEvent():
        break;                        // UI dismissed without a result
    }
  });
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

#### 4. Process payment after PIN verified

**The SDK never collects the user's PIN.** On `PinAuthenticateEvent` it returns
the merchant details and hands control back to your app. Authenticate the user
however your wallet normally does, then call:

```dart
await sdk.processPayment(orderId);
```

`orderId` must be **unique per transaction** and alphanumeric — for example
`TXN` followed by 12 digits. Reusing an id causes the payment to be rejected.

`MerchantDetails` provides `merchantName`, `amount` and `currency` so you can
show what is being paid on your own confirmation screen.

#### 5. Read the payment result

`PaymentSuccessEvent` and `PaymentFailureEvent` both carry a `PaymentResult`,
with the same fields on Android and iOS:

```dart
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
```

| Field | Type | Description |
| --- | --- | --- |
| `responseStatus` | `String?` | Status of the transaction returned by the gateway |
| `responseMessage` | `String?` | Human-readable message describing the outcome |
| `gatewayReferenceId` | `String?` | TerraPay gateway reference for the transaction; quote it to support |
| `orderId` | `String?` | The order id you passed to `processPayment` |
| `merchantId` | `String?` | ID of the merchant that was paid |
| `merchantName` | `String?` | Name of the merchant that was paid |
| `merchantAmount` | `String?` | Amount credited to the merchant, in `merchantCurrency` |
| `merchantCurrency` | `String?` | Merchant's currency, ISO 4217 |
| `subscriberAmount` | `String?` | Amount debited from the subscriber, in `subscriberCurrency` |
| `subscriberCurrency` | `String?` | Subscriber's currency, ISO 4217 |

Every field is nullable, so check for `null` before displaying or storing a
value:

```dart
case PaymentSuccessEvent(:final result):
  print('Order ${result.orderId} paid, ref ${result.gatewayReferenceId}');
  if (result.merchantName != null) {
    print('Paid ${result.merchantName} '
        '${result.merchantCurrency} ${result.merchantAmount}');
  }

case PaymentFailureEvent(:final result):
  print('Payment failed: ${result.responseMessage ?? 'unknown error'}');
```

## ⚠️ Error codes

`SdkErrorEvent.code`, and the `code` on a thrown `PlatformException`:

| Code | Message |
| --- | --- |
| `ERR_INVALID_CONTEXT` | Context must be ComponentActivity - an Activity or Application context (`MainActivity` must extend `FlutterFragmentActivity`). |
| `ERR_INVALID_ACCESS_TOKEN` | Access Token is invalid or empty. |
| `ERR_INVALID_REFRESH_TOKEN` | Refresh Token is invalid or empty. |
| `ERR_INVALID_DIAL_CODE` | Dial code format is invalid. |
| `ERR_INVALID_MSISDN` | MSISDN format is invalid or empty. |
| `ERR_INVALID_SUBSCRIBER_NAME` | Subscriber name is empty or invalid. |
| `ERR_INVALID_COUNTRY_CODE` | Subscriber country code is not a valid ISO 3166-1 alpha-2 code. |
| `ERR_INVALID_COUNTRY_NAME` | Subscriber country name is empty or invalid. (Android) |
| `ERR_INVALID_SUBSCRIBER_COUNTRY` | Subscriber country is invalid. (iOS) |
| `ERR_INVALID_CURRENCY` | Subscriber currency code is not a valid ISO 4217 code. |
| `ERR_INVALID_PRIMARY_COLOR` | Primary color must be a valid hex string format (e.g., #FFFFFF). |
| `ERR_INVALID_SECONDARY_COLOR` | Secondary color must be a valid hex string format (e.g., #FFFFFF). |
| `ERR_INVALID_WALLET_BALANCE` | Wallet balance must be a number greater than zero. |
| `ERR_INSUFFICIENT_BALANCE` | You don't have enough wallet balance to perform transactions. (Android) |
| `ERR_INVALID_TRANSACTION_ID` | TransactionId is required to process the payment. (`processPayment` called with an empty order id; thrown as a `PlatformException` on Android, delivered as an `SdkErrorEvent` on iOS.) |

### Merchant and transaction-limit parameters

Validation of the optional `merchantCountry`, `merchantAcquirer`,
`transactionMinLimit` and `transactionMaxLimit` parameters. Values left out
(or empty strings) are skipped; only values you provide are checked.

| Code | Message |
| --- | --- |
| `ERR_INVALID_MERCHANT_COUNTRY_CODE` | Merchant country code is not a valid ISO 3166-1 alpha-2 code. (iOS reports this as `ERR_INVALID_MERCHANT_COUNTRY`.) |
| `ERR_INVALID_MERCHANT_ACQUIRER` | Merchant acquirer format is invalid. |
| `ERR_MERCHANT_REQUIRED` | Merchant country is required when merchant acquirer is provided. |
| `ERR_INVALID_TRANSACTION_MINLIMIT` | Minimum transaction limit must be greater than zero. |
| `ERR_INVALID_TRANSACTION_MAXLIMIT` | Maximum transaction limit must be greater than zero. |
| `ERR_INVALID_TRANSACTION_LIMIT_RANGE` | Minimum transaction limit cannot be greater than maximum transaction limit. |

## 🧩 Troubleshooting

| Symptom | Cause |
| --- | --- |
| `ERR_INVALID_CONTEXT` on first launch | `MainActivity` still extends `FlutterActivity` |
| `MissingPluginException … com.terrapay.paybywallet/sdk` | Full restart needed after adding the dependency — hot reload does not register plugins |
| Blank white screen on launch (built with Xcode 27+) | Missing `UIApplicationSceneManifest` |
| Camera preview black, or crash when scanning | `NSCameraUsageDescription` missing, or camera permission denied |
| Release build works but payments silently fail | Custom ProGuard rules stripping the SDK — the package ships the required keep-rules, do not exclude them |
| Gradle fails with a bare version number | Wrong JDK; build with JDK 17 |

## 🔐 License

Released under the MIT License. See [LICENSE](LICENSE).

## 📬 Contact

For support or inquiries, email: sdk-support@terrapay.com
