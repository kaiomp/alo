package chat.chama.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * One Flutter engine per process, shared by the screen and by pushes
 * (FluffyChat does the same). A push that arrives while the app is closed
 * starts this engine without a screen; opening the app then shows it, so
 * there is only ever one Matrix client and one open database.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = engine(context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // No super call: the engine registers its plugins itself (see
        // engine()); registering them twice breaks plugins that keep state.
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
                (applicationContext.getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
                result.success(null)
            }
    }

    companion object {
        private var cached: FlutterEngine? = null

        private fun engine(context: Context): FlutterEngine =
            cached ?: FlutterEngine(context.applicationContext, emptyArray(), true, false).also { cached = it }

        /** The app's engine, started without a screen when the app is not running. */
        fun runningEngine(context: Context): FlutterEngine =
            cached ?: engine(context).apply {
                localizationPlugin.sendLocalesToFlutter(context.resources.configuration)
                // lib/main.dart backgroundStartArg
                dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault(),
                    listOf("--chama-background"),
                )
            }
    }
}
