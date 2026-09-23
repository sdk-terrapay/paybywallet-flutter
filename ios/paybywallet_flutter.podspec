#
# Flutter bindings for the TerraPay PayByWallet iOS SDK.
# Run `pod lib lint paybywallet_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'paybywallet_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Flutter bindings for the TerraPay PayByWallet SDK.'
  s.description      = <<-DESC
Merchant payments by QR code or merchant ID, backed by the native
TerraPayWalletSDK.
                       DESC
  s.homepage         = 'https://www.terrapay.com'
  s.license          = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author           = { 'TerraPay' => 'sdk-support@terrapay.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # The pre-built SDK travels with the plugin, so embedding apps need no
  # manual framework wiring.
  s.vendored_frameworks = 'Frameworks/TerraPayWalletSDK.xcframework'

  # The SDK is built for iOS 15.0+.
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
  s.resource_bundles = { 'paybywallet_flutter_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
end
