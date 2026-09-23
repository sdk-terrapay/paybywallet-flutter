# Maintaining paybywallet_flutter

Internal notes for whoever refreshes the bundled native SDKs. Integrators do
not need any of this — see [README.md](README.md).

## The bundled SDKs

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
