package com.terrapay.paybywallet_flutter

import android.app.Activity
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import com.terrapay.payByWallet.network.MerchantDetailsModel
import com.terrapay.payByWallet.network.PaymentResponse
import com.terrapay.payByWallet.network.TerraPayClient
import com.terrapay.payByWallet.network.TerraPayConfig
import com.terrapay.payByWallet.network.TerraPayResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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
    private val main = Handler(Looper.getMainLooper())

    // ---- Lifecycle ----------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
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
            "INVALID_CONTEXT",
            "PayByWallet needs a ComponentActivity. Make your MainActivity extend " +
                "io.flutter.embedding.android.FlutterFragmentActivity instead of FlutterActivity.",
            null,
        )
        return null
    }

    private fun launch(call: MethodCall, result: MethodChannel.Result) {
        val activity = requireComponentActivity(result) ?: return

        val balance = when (val raw = call.argument<Any>("walletBalance")) {
            is Number -> raw.toDouble()
            is String -> raw.toDoubleOrNull()
            else -> null
        }
        if (balance == null) {
            result.error("INVALID_WALLET_BALANCE", "walletBalance must be a number.", null)
            return
        }

        val config = TerraPayConfig(
            primaryColor = call.argument<String>("primaryColor").orEmpty(),
            secondaryColor = call.argument<String>("secondaryColor").orEmpty(),
            subscriberDialCode = call.argument<String>("subscriberDialCode").orEmpty(),
            subscriberMSISDN = call.argument<String>("subscriberMSISDN").orEmpty(),
            walletBalance = balance,
            subscriberCountryName = call.argument<String>("subscriberCountryName").orEmpty(),
            subscriberCountry = call.argument<String>("subscriberCountry").orEmpty(),
            subscriberCurrency = call.argument<String>("subscriberCurrency").orEmpty(),
            subscriberName = call.argument<String>("subscriberName").orEmpty(),
            accessToken = call.argument<String>("accessToken").orEmpty(),
            refreshToken = call.argument<String>("refreshToken").orEmpty(),
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
            referenceNumber = call.argument<String>("referenceNumber"),
            terraPayResult = callbacks,
        )
        result.success(null)
    }

    private fun processPayment(call: MethodCall, result: MethodChannel.Result) {
        val activity = requireComponentActivity(result) ?: return
        val transactionId = call.argument<String>("transactionId")
        if (transactionId.isNullOrBlank()) {
            result.error("INVALID_TRANSACTION_ID", "transactionId is required.", null)
            return
        }
        TerraPayClient.processPayment(context = activity, transactionId = transactionId)
        result.success(null)
    }

    // ---- Native -> Dart -----------------------------------------------------

    private fun send(method: String, args: Map<String, Any?>) {
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

        override fun onPaymentSuccess(paymentResponse: PaymentResponse) =
            send("onPaymentSuccess", paymentResponse.toMap())

        override fun onPaymentFailure(paymentResponse: PaymentResponse) =
            send("onPaymentFailure", paymentResponse.toMap())

        override fun onError(errorCode: String, message: String) =
            send("onError", mapOf("code" to errorCode, "message" to message))

        override fun onCancelled(errorCode: String, message: String) =
            send("onCancelled", mapOf("code" to errorCode, "message" to message))
    }

    private fun PaymentResponse.toMap(): Map<String, Any?> = mapOf(
        "responseCode" to responseCode,
        "responseMessage" to responseMessage,
        "gatewayReferenceId" to gatewayReferenceId,
        "orderId" to orderId,
    )
}
