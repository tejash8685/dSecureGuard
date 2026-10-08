package com.example.dharmaj_flutter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class ActivationMonitorService : Service() {
    companion object {
        private const val MONITOR_ID = 7310
        @Volatile var activityVisible = false
        fun start(context: Context, token: String, apiUrl: String, expiresAt: Long) {
            val uri = URI(apiUrl)
            require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null)
            require(token.isNotBlank() && expiresAt > System.currentTimeMillis())
            val intent = Intent(context, ActivationMonitorService::class.java)
                .putExtra("token", token).putExtra("apiUrl", apiUrl.trimEnd('/')).putExtra("expiresAt", expiresAt)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
        fun stop(context: Context) {
            MonitorSessionStore.clear(context)
            context.stopService(Intent(context, ActivationMonitorService::class.java))
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.cancel(7311)
        }
    }
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var job: ScheduledFuture<*>? = null
    @Volatile private var generation = 0
    @Volatile private var destroyed = false
    private val expiry = Runnable { stopMonitoring(true) }
    private val manager get() = getSystemService(NotificationManager::class.java)

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = monitorNotification()
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(MONITOR_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(MONITOR_ID, notification)
            var session = MonitorSessionStore.read(this)
            val token = intent?.getStringExtra("token")
            if (!token.isNullOrEmpty()) {
                if (session?.optString("token") != token) session = JSONObject().put("seen", JSONArray()).put("initialized", false)
                session!!.put("token", token).put("apiUrl", intent.getStringExtra("apiUrl"))
                    .put("expiresAt", intent.getLongExtra("expiresAt", 0))
                MonitorSessionStore.write(this, session)
            }
            if (session == null || session.optLong("expiresAt") <= System.currentTimeMillis()) {
                stopMonitoring(true); return START_NOT_STICKY
            }
            val current = ++generation
            job?.cancel(true)
            main.removeCallbacks(expiry)
            main.postDelayed(expiry, session.optLong("expiresAt") - System.currentTimeMillis())
            job = executor.scheduleWithFixedDelay({ poll(current) }, 0, 30, TimeUnit.SECONDS)
            return START_STICKY
        } catch (_: Exception) {
            Log.w("ActivationMonitor", "Background monitoring could not start.")
            stopMonitoring(false); return START_NOT_STICKY
        }
    }
    private fun poll(current: Int) {
        if (destroyed || current != generation) return
        var connection: HttpURLConnection? = null
        try {
            val session = MonitorSessionStore.read(this) ?: return
            val token = session.getString("token")
            if (session.optLong("expiresAt") <= System.currentTimeMillis()) {
                main.post { if (current == generation) stopMonitoring(true) }; return
            }
            connection = URL(session.getString("apiUrl") + "/activations/notifications").openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Authorization", "Bearer $token")
            val status = connection.responseCode
            if (status == 401) {
                main.post { if (current == generation) stopMonitoring(true) }; return
            }
            if (status != 200) return
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val response = JSONObject(body)
            if (!response.optBoolean("success")) return
            val requests = response.getJSONObject("data").optJSONArray("requests") ?: JSONArray()
            val seenArray = session.optJSONArray("seen") ?: JSONArray()
            val seen = (0 until seenArray.length()).map { seenArray.getString(it) }.toMutableSet()
            val fresh = mutableListOf<JSONObject>()
            for (i in 0 until requests.length()) {
                val row = requests.getJSONObject(i)
                val key = row.optInt("activationID").toString() + "|" + row.optString("requestDate")
                if (seen.add(key)) fresh.add(row)
            }
            synchronized(MonitorSessionStore) {
                if (destroyed || current != generation || MonitorSessionStore.read(this)?.optString("token") != token) return
                val initialized = session.optBoolean("initialized")
                // Store only the latest bounded history, keeping the returned pending list first.
                val keys = (0 until requests.length()).map { requests.getJSONObject(it).let { r -> "${r.optInt("activationID")}|${r.optString("requestDate")}" } }
                session.put("seen", JSONArray((keys + seen).distinct().take(500))).put("initialized", true)
                MonitorSessionStore.write(this, session)
                if (initialized && fresh.isNotEmpty() && !activityVisible) notifyRequests(fresh)
            }
        } catch (_: Exception) {
            // Network failures retain the session and are retried without logging credentials.
        } finally { connection?.disconnect() }
    }
    private fun monitorNotification(): Notification {
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("activation_monitor", "Background activation monitoring", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, MONITOR_ID, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "activation_monitor") else Notification.Builder(this)
        return builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Monitoring activation requests")
            .setContentText("Checking for new requests while you are signed in.").setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE).build()
    }
    private fun notifyRequests(rows: List<JSONObject>) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("activation_status", "Activation status", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(this, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("activation_notification", true); putExtra("activation_status", "Pending")
        }
        val open = PendingIntent.getActivity(this, 7311, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "activation_status") else Notification.Builder(this)
        val body = "${rows.size} new activation request${if (rows.size == 1) "" else "s"} waiting for review."
        manager.notify(7311, builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("New activation request")
            .setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(open).setAutoCancel(true).build())
    }
    private fun stopMonitoring(clear: Boolean) {
        ++generation; job?.cancel(true); main.removeCallbacks(expiry)
        if (clear) { MonitorSessionStore.clear(this); manager.cancel(7311) }
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopMonitoring(false) }
    override fun onDestroy() {
        destroyed = true; ++generation; job?.cancel(true); executor.shutdownNow()
        main.removeCallbacksAndMessages(null); super.onDestroy()
    }
}
