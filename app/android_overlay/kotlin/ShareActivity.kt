package it.matteo.bet_tracker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Riceve lo screenshot condiviso (es. da Eplay), lo registra in background con il codice Dart
 * (entrypoint `shareMain`) e si chiude subito: l'app non si apre.
 */
class ShareActivity : Activity() {
    private var engine: FlutterEngine? = null
    private var finished = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val paths = copyShared(intent)
        if (paths.isEmpty()) {
            Toast.makeText(applicationContext, "Bet Tracker: nessuna immagine ricevuta", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        Toast.makeText(applicationContext, "Bet Tracker: leggo la schedina…", Toast.LENGTH_SHORT).show()
        // lascia subito l'utente dov'era, il lavoro continua in background
        moveTaskToBack(true)

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationCompleteAsync(applicationContext, null, handler) {
            val e = FlutterEngine(applicationContext)
            engine = e
            MethodChannel(e.dartExecutor.binaryMessenger, "bet_tracker/share").setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPaths" -> result.success(paths)
                    "done" -> {
                        result.success(null)
                        done(call.arguments as? String ?: "Schedina registrata")
                    }
                    else -> result.notImplemented()
                }
            }
            e.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "shareMain")
            )
        }
        handler.postDelayed({ done("Bet Tracker: ci ho messo troppo, apri l'app per controllare") }, 45_000)
    }

    private fun done(msg: String) {
        if (finished) return
        finished = true
        Toast.makeText(applicationContext, msg, Toast.LENGTH_LONG).show()
        try {
            MainActivity.channel?.invokeMethod("reload", null)
        } catch (e: Exception) {
        }
        handler.post {
            try {
                engine?.destroy()
            } catch (e: Exception) {
            }
            engine = null
            finish()
        }
    }

    @Suppress("DEPRECATION")
    private fun copyShared(intent: Intent?): ArrayList<String> {
        val out = ArrayList<String>()
        if (intent == null) return out
        val uris = ArrayList<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        }
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        for ((i, uri) in uris.withIndex()) {
            try {
                val f = File(dir, "share_${System.currentTimeMillis()}_$i.jpg")
                contentResolver.openInputStream(uri)?.use { input ->
                    f.outputStream().use { input.copyTo(it) }
                }
                if (f.exists() && f.length() > 0) out.add(f.absolutePath)
            } catch (e: Exception) {
            }
        }
        return out
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
