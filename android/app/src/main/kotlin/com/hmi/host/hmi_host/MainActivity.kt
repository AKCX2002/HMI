package com.hmi.host.hmi_host

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var androidUsbSerialBridge: AndroidUsbSerialBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        androidUsbSerialBridge =
            AndroidUsbSerialBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        androidUsbSerialBridge?.dispose()
        androidUsbSerialBridge = null
        super.onDestroy()
    }
}
