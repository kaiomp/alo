package chat.chama.app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import org.unifiedpush.flutter.connector.UnifiedPushService

/** Delivers pushes to the app's own engine instead of a second one (see MainActivity). */
class ChamaPushService : UnifiedPushService() {
    override fun getEngine(context: Context): FlutterEngine = MainActivity.runningEngine(context)
}
