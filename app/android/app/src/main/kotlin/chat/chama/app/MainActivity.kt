package chat.chama.app

import android.content.ClipData
import android.content.ClipboardManager
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // lib/common/secure_clipboard.dart: the recovery key is copied as
        // sensitive, so clipboard previews and keyboard histories hide it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chat.chama.app/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "copySensitive") return@setMethodCallHandler result.notImplemented()
                val clip = ClipData.newPlainText("", call.arguments as String)
                // ClipDescription.EXTRA_IS_SENSITIVE (API 33); older versions read the same key.
                clip.description.extras = PersistableBundle().apply {
                    putBoolean("android.content.extra.IS_SENSITIVE", true)
                }
                (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
                result.success(null)
            }
    }
}
