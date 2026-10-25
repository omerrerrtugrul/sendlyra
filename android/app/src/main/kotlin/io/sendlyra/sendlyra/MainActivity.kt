package io.sendlyra.sendlyra

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// P-01: Android "Paylaş" menüsü (ACTION_SEND / ACTION_SEND_MULTIPLE).
///
/// Gelen içerik URI'leri cache klasörüne kopyalanır (content:// yolları
/// doğrudan dosya yolu değildir); Flutter tarafına {"text", "files"} haritası
/// olarak iletilir. Uygulama kapalıyken gelen paylaşım [initialItems]'ta
/// bekler, Flutter hazır olunca `getInitialItems` ile alınır.
class MainActivity : FlutterActivity() {
    private val channelName = "io.sendlyra/share_intent"
    private var channel: MethodChannel? = null
    private var initialItems: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, channelName
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialItems" -> {
                        val items = initialItems
                        initialItems = null
                        result.success(items)
                    }
                    "clearInitial" -> {
                        initialItems = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Motor hazır; onCreate sırasında beklemiş paylaşımı hemen ilet.
        initialItems?.let { items ->
            channel?.invokeMethod("onShared", items)
            initialItems = null
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        val items = parseShare(intent) ?: return
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onShared", items)
        } else {
            initialItems = items
        }
    }

    /// Paylaşım niyetini {"text", "files": [{"path", "name"}]} haritasına çevirir.
    private fun parseShare(intent: Intent?): Map<String, Any?>? {
        val action = intent?.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
        val uris: List<Uri> = when (action) {
            Intent.ACTION_SEND -> listOfNotNull(parcelableUri(intent, Intent.EXTRA_STREAM))
            else -> parcelableUriList(intent, Intent.EXTRA_STREAM)
        }
        val files = mutableListOf<Map<String, String>>()
        for (uri in uris) {
            copyToCache(uri)?.let { files.add(it) }
        }
        if (files.isEmpty() && text == null) return null
        return mapOf("text" to text, "files" to files)
    }

    @Suppress("DEPRECATION")
    private fun parcelableUri(intent: Intent, key: String): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(key, Uri::class.java)
        } else {
            intent.getParcelableExtra(key) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun parcelableUriList(intent: Intent, key: String): List<Uri> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(key, Uri::class.java) ?: emptyList()
        } else {
            (intent.getParcelableArrayListExtra(key) as? List<*>)?.filterIsInstance<Uri>()
                ?: emptyList()
        }

    /// İçerik URI'sini cache'e kopyalar; görünen adı korur.
    private fun copyToCache(uri: Uri): Map<String, String>? = try {
        val name = queryDisplayName(uri)
            ?: "shared-${System.currentTimeMillis()}"
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val safeName = name.replace(Regex("[/\\\\]"), "_")
        val out = File(dir, "${System.currentTimeMillis()}-$safeName")
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { src -> out.outputStream().use { dst -> src.copyTo(dst) } }
        mapOf("path" to out.absolutePath, "name" to name)
    } catch (e: Exception) {
        null
    }

    private fun queryDisplayName(uri: Uri): String? = try {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
        }
    } catch (e: Exception) {
        null
    }
}
