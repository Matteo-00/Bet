package it.matteo.bet_tracker

import android.app.Notification
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/** Coda condivisa tra il servizio e l'app (SharedPreferences). */
object NotificationQueue {
    const val PREFS = "bet_tracker_notifications"
    const val KEY_QUEUE = "queue"
    const val KEY_FILTER = "filter"

    @Synchronized
    fun add(ctx: Context, obj: JSONObject) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = try { JSONArray(p.getString(KEY_QUEUE, "[]")) } catch (e: Exception) { JSONArray() }
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optString("text") == obj.optString("text") &&
                o.optString("title") == obj.optString("title") &&
                Math.abs(o.optLong("time") - obj.optLong("time")) < 60_000) return
        }
        arr.put(obj)
        val out = JSONArray()
        val from = if (arr.length() > 100) arr.length() - 100 else 0
        for (i in from until arr.length()) out.put(arr.get(i))
        p.edit().putString(KEY_QUEUE, out.toString()).apply()
    }

    @Synchronized
    fun drain(ctx: Context): String {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val s = p.getString(KEY_QUEUE, "[]") ?: "[]"
        p.edit().putString(KEY_QUEUE, "[]").apply()
        return s
    }

    fun keywords(ctx: Context): List<String> {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return (p.getString(KEY_FILTER, "eplay") ?: "eplay")
            .split(",")
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
    }

    fun setKeywords(ctx: Context, value: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_FILTER, value).apply()
    }
}

class BetNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.packageName == packageName) return
        try {
            val n = sbn.notification ?: return
            if ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
            val extras = n.extras
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
            if (title.isBlank() && text.isBlank()) return
            val appLabel = try {
                packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
            } catch (e: Exception) {
                ""
            }
            val hay = "${sbn.packageName} $appLabel $title $text".lowercase()
            val keys = NotificationQueue.keywords(this)
            if (keys.isNotEmpty() && keys.none { hay.contains(it) }) return

            val obj = JSONObject()
            obj.put("pkg", sbn.packageName)
            obj.put("app", if (appLabel.isNotEmpty()) appLabel else sbn.packageName)
            obj.put("title", title)
            obj.put("text", text)
            obj.put("time", sbn.postTime)
            NotificationQueue.add(this, obj)

            Handler(Looper.getMainLooper()).post {
                try {
                    MainActivity.channel?.invokeMethod("changed", null)
                } catch (e: Exception) {
                }
            }
        } catch (e: Exception) {
        }
    }
}
