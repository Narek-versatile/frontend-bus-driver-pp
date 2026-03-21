package com.example.frontend_driver

import android.content.Intent
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.frontend_driver/kiosk"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val token = call.argument<String>("token")
                    val baseUrl = call.argument<String>("baseUrl")
                    val intent = Intent(this, ScannerService::class.java).apply {
                        putExtra("TOKEN", token)
                        putExtra("BASE_URL", baseUrl)
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "stopService" -> {
                    val intent = Intent(this, ScannerService::class.java).apply {
                        action = "STOP"
                    }
                    ContextCompat.startForegroundService(this, intent) // action STOP will tear it down
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
