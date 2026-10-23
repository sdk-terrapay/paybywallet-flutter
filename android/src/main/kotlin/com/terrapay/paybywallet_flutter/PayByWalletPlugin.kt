package com.terrapay.paybywallet_flutter

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import com.terrapay.payByWallet.PaymentsHomeActivity
import com.terrapay.payByWallet.network.MerchantDetailsModel
import com.terrapay.payByWallet.network.TerraPayClient
import com.terrapay.payByWallet.network.TerraPayConfig
import com.terrapay.payByWallet.network.TerraPayEnvironment
import com.terrapay.payByWallet.network.TPPaymentStatus
import com.terrapay.payByWallet.network.TerraPayResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.math.BigDecimal

/**
 * Android half of the PayByWallet bridge.
 *
 * Dart calls `launch` / `processPayment` down; the SDK's [TerraPayResult]
 * callbacks are forwarded back up the same channel on the main thread.
 */
class PayByWalletPlugin :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "com.terrapay.paybywallet/sdk"
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var application: Application? = null
    private val main = Handler(Looper.getMainLooper())

    /**
     * True while the SDK's screen is showing and has not yet reported back.
     * Some SDK exits (e.g. system back on the QR scanner) finish the activity
     * without any [TerraPayResult] callback; [sdkActivityWatcher] turns those
     * into `onClosed` so Dart is never left waiting.
     */
    private var awaitingResult = false

    // ---- Lifecycle ----------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attach(binding.activity)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attach(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detach()
    }

    override fun onDetachedFromActivity() {
        detach()
    }

    private fun attach(host: Activity) {
        activity = host
        application = host.application.also {
            it.registerActivityLifecycleCallbacks(sdkActivityWatcher)
        }
    }

    private fun detach() {
        application?.unregisterActivityLifecycleCallbacks(sdkActivityWatcher)
        application = null
        activity = null
    }

    private val sdkActivityWatcher = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityDestroyed(destroyed: Activity) {
            if (destroyed is PaymentsHomeActivity && destroyed.isFinishing && awaitingResult) {
                send("onClosed", emptyMap())
            }
        }

        override fun onActivityCreated(created: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(started: Activity) {}
        override fun onActivityResumed(resumed: Activity) {}
        override fun onActivityPaused(paused: Activity) {}
        override fun onActivityStopped(stopped: Activity) {}
        override fun onActivitySaveInstanceState(saved: Activity, outState: Bundle) {}
    }

    // ---- Dart -> native -----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "launch" -> launch(call, result)
            "processPayment" -> processPayment(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * The SDK's UI is Compose-based and it rejects any context that is not a
     * [ComponentActivity]. Flutter's default `FlutterActivity` extends plain
     * `android.app.Activity`, so the host app must use `FlutterFragmentActivity`.
     * Checking here turns an opaque SDK error into an actionable one.
     */
    private fun requireComponentActivity(result: MethodChannel.Result): ComponentActivity? {
        val current = activity
        if (current is ComponentActivity) return current
        result.error(
            "ERR_INVALID_CONTEXT",
            "PayByWallet needs a ComponentActivity. Make your MainActivity extend " +
                "io.flutter.embedding.android.FlutterFragmentActivity instead of FlutterActivity.",
            null,
        )
        return null
    }

    private fun launch(call: MethodCall, result: MethodChannel.Result) {
        val activity = requireComponentActivity(result) ?: return

        // Optional: absent leaves the balance unset, anything else must be a
        // number greater than zero. The Android SDK does not check this itself,
        // so mirror the iOS SDK's rule and error code here.
        val balance = optionalDouble(call, "walletBalance")
        if (balance != null && !(balance.isFinite() && balance > 0)) {
            result.error(
                "ERR_INVALID_WALLET_BALANCE",
                "walletBalance must be a number greater than zero.",
                null,
            )
            return
        }

        val environment = when (val env = call.argument<String>("environment")) {
            "production" -> TerraPayEnvironment.PRODUCTION
            "sandbox", null -> TerraPayEnvironment.SANDBOX
            else -> {
                result.error("INVALID_ENVIRONMENT", "Unknown environment '$env'.", null)
                return
            }
        }

        val config = TerraPayConfig(
            primaryColor = call.argument<String>("primaryColor").orEmpty(),
            secondaryColor = call.argument<String>("secondaryColor").orEmpty(),
            subscriberDialCode = call.argument<String>("subscriberDialCode").orEmpty(),
            subscriberMSISDN = call.argument<String>("subscriberMSISDN").orEmpty(),
            walletBalance = balance,
            merchantCountry = call.argument<String>("merchantCountry").orEmpty(),
            merchantAcquirer = call.argument<String>("merchantAcquirer").orEmpty(),
            transactionMinLimit = optionalDouble(call, "transactionMinLimit"),
            transactionMaxLimit = optionalDouble(call, "transactionMaxLimit"),
            subscriberCountryName = call.argument<String>("subscriberCountryName").orEmpty(),
            subscriberCountry = call.argument<String>("subscriberCountry").orEmpty(),
            subscriberCurrency = call.argument<String>("subscriberCurrency").orEmpty(),
            subscriberName = call.argument<String>("subscriberName").orEmpty(),
            accessToken = call.argument<String>("accessToken").orEmpty(),
            refreshToken = call.argument<String>("refreshToken").orEmpty(),
            environment = environment,
        )

        // Surface configuration problems as a failed call rather than as an
        // asynchronous onError, so Dart can await the launch.
        TerraPayClient.validateInputFields(activity, config)?.let { error ->
            result.error(error.code, error.message, null)
            return
        }

        TerraPayClient.init(
            context = activity,
            config = config,
            terraPayResult = callbacks,
        )
        awaitingResult = true
        result.success(null)
    }

    /** Null when absent; NaN when present but not numeric, so validation rejects it. */
    private fun optionalDouble(call: MethodCall, key: String): Double? =
        when (val raw = call.argument<Any>(key)) {
            null -> null
            is Number -> raw.toDouble()
            is String -> raw.toDoubleOrNull() ?: Double.NaN
            else -> Double.NaN
        }

    private fun processPayment(call: MethodCall, result: MethodChannel.Result) {
        val activity = requireComponentActivity(result) ?: return
        val transactionId = call.argument<String>("transactionId").orEmpty()
        // Same pre-check the SDK's processPayment runs; calling it here returns
        // the SDK's own error as a failed call, as launch does with
        // validateInputFields, instead of an asynchronous onError.
        TerraPayClient.validateOTP(transactionId)?.let { error ->
            result.error(error.code, error.message, null)
            return
        }
        TerraPayClient.processPayment(context = activity, transactionId = transactionId)
        awaitingResult = true
        result.success(null)
    }

    // ---- Native -> Dart -----------------------------------------------------

    private fun send(method: String, args: Map<String, Any?>) {
        // Any callback ends the wait; the SDK invokes them on the main thread
        // before finishing its activity, so this is set before the destroy check.
        awaitingResult = false
        main.post { channel.invokeMethod(method, args) }
    }

    private val callbacks = object : TerraPayResult {

        override fun onPinAuthenticate(merchantDetails: MerchantDetailsModel) {
            send(
                "onPinAuthenticate",
                mapOf(
                    "merchantName" to merchantDetails.merchantName,
                    "subscriberAmount" to merchantDetails.subscriberAmount,
                    "subscriberCurrency" to merchantDetails.subscriberCurrency,
                ),
            )
        }

        override fun onPaymentSuccess(paymentStatus: TPPaymentStatus) =
            send("onPaymentSuccess", paymentStatus.toMap())

        override fun onPaymentFailure(paymentStatus: TPPaymentStatus) =
            send("onPaymentFailure", paymentStatus.toMap())

        override fun onError(errorCode: String, message: String) =
            send("onError", mapOf("code" to errorCode, "message" to message))

        override fun onCancelled(errorCode: String, message: String) =
            send("onCancelled", mapOf("code" to errorCode, "message" to message))
    }

    // Same keys as the iOS bridge. The Android SDK reports amounts as Double
    // while iOS sends strings, so amounts are stringified to keep one Dart type.
    private fun TPPaymentStatus.toMap(): Map<String, Any?> = mapOf(
        "responseStatus" to responseStatus,
        "responseMessage" to responseMessage,
        "gatewayReferenceId" to gatewayReferenceId,
        "orderId" to orderId,
        "merchantId" to merchantId,
        "merchantName" to merchantName,
        "merchantAmount" to BigDecimal.valueOf(merchantAmount).toPlainString(),
        "merchantCurrency" to merchantCurrency,
        "subscriberAmount" to BigDecimal.valueOf(subscriberAmount).toPlainString(),
        "subscriberCurrency" to subscriberCurrency,
    )
}
