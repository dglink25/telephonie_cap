package com.telephonie_cap.telephonie_cap

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.telephonie_cap/service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startReverbService" -> {
                        val token      = call.argument<String>("token") ?: ""
                        val serverHost = call.argument<String>("serverHost") ?: "192.168.100.195"
                        startReverbService(token, serverHost)
                        result.success(null)
                    }
                    "stopReverbService" -> {
                        stopService(Intent(this, ReverbForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startReverbService(token: String, serverHost: String) {
        val intent = Intent(this, ReverbForegroundService::class.java).apply {
            putExtra("auth_token", token)
            putExtra("server_host", serverHost)
        }
        startForegroundService(intent)
    }

    // Gérer l'intent ANSWER_CALL depuis la notification
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "ANSWER_CALL") {
            val callId = intent.getIntExtra("call_id", 0)
            val convId = intent.getIntExtra("conv_id", 0)
            // Transmettre a Flutter via le channel
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onAnswerCall", mapOf(
                    "call_id" to callId,
                    "conv_id" to convId,
                ))
            }
        }
    }
}
