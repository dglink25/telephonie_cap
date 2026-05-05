package com.telephonie_cap.telephonie_cap

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * BUG #23 CORRIGE : CallActionReceiver manquant
 * Reçoit les actions "Refuser" des notifications d'appel entrant.
 */
class CallActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val callId    = intent.getIntExtra("call_id", 0)
        val authToken = intent.getStringExtra("auth_token") ?: ""
        val serverHost = intent.getStringExtra("server_host") ?: "192.168.100.195"

        Log.d("CallActionReceiver", "Action: ${intent.action}, callId: $callId")

        when (intent.action) {
            "REJECT_CALL" -> {
                // Annuler la notification
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(ReverbForegroundService.CALL_NOTIF_ID)

                // Appeler l'API pour rejeter l'appel (en background thread)
                if (callId > 0 && authToken.isNotEmpty()) {
                    Thread {
                        rejectCallApi(serverHost, callId, authToken)
                    }.start()
                }
            }
        }
    }

    private fun rejectCallApi(serverHost: String, callId: Int, authToken: String) {
        try {
            val client = OkHttpClient()
            val body   = "".toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("http://$serverHost:8000/api/calls/$callId/reject")
                .post(body)
                .addHeader("Authorization", "Bearer $authToken")
                .addHeader("Accept", "application/json")
                .build()
            client.newCall(request).execute().use { response ->
                Log.d("CallActionReceiver", "Reject API response: ${response.code}")
            }
        } catch (e: Exception) {
            Log.e("CallActionReceiver", "rejectCallApi error: ${e.message}")
        }
    }
}
