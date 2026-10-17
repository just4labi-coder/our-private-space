
package com.privatespace.ourspace

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingSharedText = extractSharedText(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val sharedText = extractSharedText(intent)
        if (!sharedText.isNullOrBlank()) {
            pendingSharedText = sharedText
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(
                    messenger,
                    "com.privatespace.ourspace/share_intent"
                ).invokeMethod("sharedText", sharedText)
            }
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null

        return intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.privatespace.ourspace/share_intent"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.privatespace.ourspace/media_download"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val serviceIntent =
                        Intent(this, MediaDownloadService::class.java)

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }

                    result.success(true)
                }

                "stop" -> {
                    stopService(
                        Intent(this, MediaDownloadService::class.java)
                    )
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
