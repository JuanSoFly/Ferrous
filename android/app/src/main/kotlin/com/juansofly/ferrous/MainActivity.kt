package com.juansofly.ferrous

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var safHandler: SafHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        safHandler = SafHandler(this)
        
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
