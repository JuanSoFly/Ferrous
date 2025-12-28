package com.juansofly.ferrous

import android.app.ActivityManager
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var safHandler: SafHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // CRITICAL FIX: Set task description for recent apps/task switcher icon
        // Without this, Android shows the default robot icon in the recent apps view
        try {
            val icon = BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
            val taskDescription = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ActivityManager.TaskDescription(
                    getString(R.string.app_name),
                    R.mipmap.ic_launcher
                )
            } else {
                @Suppress("DEPRECATION")
                ActivityManager.TaskDescription(
                    getString(R.string.app_name),
                    icon
                )
            }
            setTaskDescription(taskDescription)
        } catch (e: Exception) {
            // Fallback if icon loading fails, just log it
            android.util.Log.e("MainActivity", "Failed to set task description", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        safHandler = SafHandler(this)
        
        // Clean up temp file cache on startup (Plan 05)
        safHandler.cleanupSafCache()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SafHandler.CHANNEL)
            .setMethodCallHandler { call, result ->
                safHandler.handleMethodCall(call, result)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        safHandler.handleActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::safHandler.isInitialized) {
            safHandler.dispose()
        }
    }
}
