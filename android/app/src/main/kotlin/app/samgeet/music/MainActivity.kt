package app.samgeet.music

import android.Manifest
import android.app.SearchManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null

    // A shared song/playlist link that opened the app. Handed to Dart once, then forgotten.
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLink = linkFrom(intent)
        // Android 13+ hides notifications until the user allows them. Without this
        // the playback notification and lock-screen controls would never appear.
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.samgeet.music/links").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "initialLink") {
                    result.success(pendingLink)
                    pendingLink = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    // The app was already running (singleTop) and the user tapped another shared link.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        linkFrom(intent)?.let { channel?.invokeMethod("link", it) }
    }

    // A voice "play <query>" request (Bixby, Google Assistant) becomes samgeet://play?q=<query>, so Dart
    // receives it through the same channel as shared links. An empty query means just "play music".
    private fun linkFrom(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.dataString
        MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH ->
            Uri.Builder().scheme("samgeet").authority("play")
                .appendQueryParameter("q", intent.getStringExtra(SearchManager.QUERY).orEmpty())
                .build().toString()
        else -> null
    }
}
