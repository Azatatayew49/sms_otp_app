package com.shounakmulay.telephony

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Ak Ulag addition: runs a USSD code (e.g. a balance check) without the dialer
 * and returns the network's text reply. Uses the SIM that sends SMS.
 * Registered on every engine, so it also works from a background service isolate.
 */
class UssdHandler(private val context: Context) : MethodChannel.MethodCallHandler {

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    if (call.method != "sendUssd") {
      result.notImplemented()
      return
    }
    val code = call.argument<String>("code")
    if (code.isNullOrBlank()) {
      result.error("ILLEGAL_ARGUMENT", "USSD code is missing", null)
      return
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      result.error("UNSUPPORTED", "USSD needs Android 8 or newer", null)
      return
    }
    if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE)
      != PackageManager.PERMISSION_GRANTED
    ) {
      result.error("PERMISSION", "Phone (call) permission is not granted", null)
      return
    }
    try {
      var telephony = context.getSystemService(TelephonyManager::class.java)
      if (telephony == null) {
        result.error("UNAVAILABLE", "No telephony service", null)
        return
      }
      val subId = SmsManager.getDefaultSmsSubscriptionId()
      if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
        telephony = telephony.createForSubscriptionId(subId)
      }
      var answered = false
      telephony.sendUssdRequest(code, object : TelephonyManager.UssdResponseCallback() {
        override fun onReceiveUssdResponse(tm: TelephonyManager, request: String, response: CharSequence) {
          if (answered) return
          answered = true
          result.success(response.toString())
        }

        override fun onReceiveUssdResponseFailed(tm: TelephonyManager, request: String, failureCode: Int) {
          if (answered) return
          answered = true
          result.error("USSD_FAILED", "The network did not answer the USSD request (code $failureCode)", null)
        }
      }, Handler(Looper.getMainLooper()))
    } catch (e: SecurityException) {
      result.error("PERMISSION", e.message ?: "Not allowed to run USSD", null)
    } catch (e: RuntimeException) {
      result.error("USSD_FAILED", e.message ?: "USSD request failed", null)
    }
  }
}
