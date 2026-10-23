package io.sendlyra.sendlyra

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MulticastLock: Android çekirdeği, ekran kapalıyken veya uyku
 * modunda multicast paketlerini atabilir. Keşif beacon'larının
 * kesintisiz alınması için WifiManager.MulticastLock tutulur.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sendlyra/multicast"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    try {
                        val lock = multicastLock
                        if (lock == null) {
                            val wifi = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("sendlyra-discovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        } else if (!lock.isHeld) {
                            lock.acquire()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "release" -> {
                    try {
                        val lock = multicastLock
                        if (lock != null && lock.isHeld) lock.release()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
