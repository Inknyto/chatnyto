package com.example.chatnyto

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var adbBridge: AdbBridgePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = AdbBridgePlugin(applicationContext)
        adbBridge = bridge
        bridge.attach()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AdbBridgePlugin.CHANNEL,
        ).setMethodCallHandler(bridge)
    }

    override fun onDestroy() {
        adbBridge?.detach()
        adbBridge = null
        super.onDestroy()
    }
}
