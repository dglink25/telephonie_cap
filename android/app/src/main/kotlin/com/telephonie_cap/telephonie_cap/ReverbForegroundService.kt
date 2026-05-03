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
        .pingInterval(30, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()
    
    private var authToken: String? = null
    private var serverHost: String = "192.168.100.195" // sera mis à jour
    
    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildPersistentNotification())
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        authToken = intent?.getStringExtra("auth_token")
        serverHost = intent?.getStringExtra("server_host") ?: serverHost
        connectWebSocket()
        return START_STICKY // redémarrer automatiquement si tué
    }
    
    private fun connectWebSocket() {
        val url = "ws://$serverHost:8080/app/xtsedffitwzc6vpwl7tz?protocol=7&client=android&version=1.0"
        val request = Request.Builder().url(url).build()
        
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w("ReverbService", "WS error: ${t.message}")
                reconnect()
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                reconnect()
            }
        })
    }
    
    private fun handleMessage(text: String) {
        val msg = JSONObject(text)
        val event = msg.optString("event")
        val data = try { JSONObject(msg.optString("data", "{}")) } catch(e: Exception) { JSONObject() }
        
        when (event) {
            "call.initiated" -> showIncomingCallNotification(data)
            "call.status" -> {
                val status = data.optString("status")
                if (status in listOf("ended", "rejected", "missed")) {
                    cancelCallNotification()
                }
            }
        }
    }
    
    private fun showIncomingCallNotification(data: JSONObject) {
        val caller = data.optJSONObject("caller")
        val callerName = caller?.optString("full_name") ?: "Appel entrant"
        val callType = data.optString("type", "audio")
        val callId = data.optInt("call_id", data.optInt("id", 0))
        val convId = data.optInt("conversation_id", 0)
        
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val answerIntent = Intent(this, MainActivity::class.java).apply {
            action = "ANSWER_CALL"
            putExtra("call_id", callId)
            putExtra("conv_id", convId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val rejectIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = "REJECT_CALL"
            putExtra("call_id", callId)
        }
        
        val answerPI = PendingIntent.getActivity(this, callId, answerIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val rejectPI = PendingIntent.getBroadcast(this, callId + 1000, rejectIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        
        val emoji = if (callType == "video") "" else ""
        
        val notif = NotificationCompat.Builder(this, "calls")
            .setContentTitle(callerName)
            .setContentText("$emoji Appel $callType entrant...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(answerPI, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(0, "Refuser", rejectPI)
            .addAction(0, "Répondre", answerPI)
            .build()
        
        nm.notify(CALL_NOTIF_ID, notif)
    }
    
    private fun cancelCallNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CALL_NOTIF_ID)
    }
    
    private fun reconnect() {
        android.os.Handler(mainLooper).postDelayed({ connectWebSocket() }, 5000)
    }
    
    private fun buildPersistentNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel("persistent", "Service actif", NotificationManager.IMPORTANCE_LOW)
        nm.createNotificationChannel(channel)
        
        return NotificationCompat.Builder(this, "persistent")
            .setContentTitle("Téléphonie CAP")
            .setContentText("En attente d'appels...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    companion object {
        const val NOTIF_ID = 1
        const val CALL_NOTIF_ID = 2
    }
}