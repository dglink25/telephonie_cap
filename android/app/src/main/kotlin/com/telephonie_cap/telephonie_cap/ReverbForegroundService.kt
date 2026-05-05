package com.telephonie_cap.telephonie_cap

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import okhttp3.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ReverbForegroundService : Service() {

    private var webSocket: WebSocket? = null
    private val client = OkHttpClient.Builder()
        .pingInterval(25, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    private var authToken: String? = null
    private var serverHost: String = "192.168.100.195"

    companion object {
        const val NOTIF_ID      = 1
        const val CALL_NOTIF_ID = 2
        const val APP_KEY       = "xtsedffitwzc6vpwl7tz"
    }

    override fun onCreate() {
        super.onCreate()
        _createNotificationChannels()
        startForeground(NOTIF_ID, _buildPersistentNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        authToken  = intent?.getStringExtra("auth_token")
        serverHost = intent?.getStringExtra("server_host") ?: serverHost
        _connectWebSocket()
        return START_STICKY
    }

    private fun _connectWebSocket() {
        val url = "ws://$serverHost:8080/app/$APP_KEY?protocol=7&client=android&version=8.3.0"
        Log.d("ReverbService", "Connexion WebSocket: $url")
        val request = Request.Builder().url(url).build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d("ReverbService", "WebSocket ouvert")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                _handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w("ReverbService", "WS error: ${t.message}")
                _reconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d("ReverbService", "WS fermé: $code $reason")
                _reconnect()
            }
        })
    }

    private fun _handleMessage(text: String) {
        try {
            val msg   = JSONObject(text)
            val event = msg.optString("event")
            val data  = try { JSONObject(msg.optString("data", "{}")) } catch (e: Exception) { JSONObject() }

            when (event) {
                "pusher:connection_established" -> {
                    val socketId = data.optString("socket_id")
                    Log.d("ReverbService", "Connecté, socket: $socketId")
                }
                "call.initiated" -> _showIncomingCallNotification(data)
                "call.status"    -> {
                    val status = data.optString("status")
                    if (status in listOf("ended", "rejected", "missed")) {
                        _cancelCallNotification()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("ReverbService", "handleMessage error: ${e.message}")
        }
    }

    private fun _showIncomingCallNotification(data: JSONObject) {
        val caller     = data.optJSONObject("caller")
        val callerName = caller?.optString("full_name") ?: "Appel entrant"
        val callType   = data.optString("type", "audio")
        val callId     = data.optInt("call_id", data.optInt("id", 0))
        val convId     = data.optInt("conversation_id", 0)

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val answerIntent = Intent(this, MainActivity::class.java).apply {
            action = "ANSWER_CALL"
            putExtra("call_id", callId)
            putExtra("conv_id", convId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        // BUG #23 CORRIGÉ : utiliser CallActionReceiver (qui existe maintenant)
        val rejectIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = "REJECT_CALL"
            putExtra("call_id",     callId)
            putExtra("auth_token",  authToken ?: "")
            putExtra("server_host", serverHost)
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val answerPI = PendingIntent.getActivity(this, callId,        answerIntent, flags)
        val rejectPI = PendingIntent.getBroadcast(this, callId + 1000, rejectIntent, flags)

        val emoji = if (callType == "video") "📹" else "📞"

        val notif = NotificationCompat.Builder(this, "calls")
            .setContentTitle(callerName)
            .setContentText("$emoji Appel $callType entrant...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(answerPI, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, "❌ Refuser",  rejectPI)
            .addAction(0, "✅ Répondre", answerPI)
            .build()

        nm.notify(CALL_NOTIF_ID, notif)
        Log.d("ReverbService", "Notification appel affiché: $callerName")
    }

    private fun _cancelCallNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CALL_NOTIF_ID)
    }

    private fun _reconnect() {
        android.os.Handler(mainLooper).postDelayed({
            if (authToken != null) _connectWebSocket()
        }, 5000)
    }

    private fun _createNotificationChannels() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Canal service persistant
        val persistentChannel = NotificationChannel(
            "persistent", "Service actif",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Service Téléphonie CAP actif" }
        nm.createNotificationChannel(persistentChannel)

        // Canal appels entrants
        val callsChannel = NotificationChannel(
            "calls", "Appels entrants",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description    = "Notifications d'appels entrants"
            enableVibration(true)
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(callsChannel)
    }

    private fun _buildPersistentNotification(): Notification {
        return NotificationCompat.Builder(this, "persistent")
            .setContentTitle("Téléphonie CAP")
            .setContentText("En attente d'appels...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        webSocket?.close(1000, "Service arrêté")
        client.dispatcher.executorService.shutdown()
        super.onDestroy()
    }
}
