package com.example.dharmaj_flutter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deviceChannel: MethodChannel? = null
    private var pendingMonitor: Map<String, Any>? = null

    override fun onStart() { super.onStart(); ActivationMonitorService.activityVisible = true }
    override fun onStop() { ActivationMonitorService.activityVisible = false; super.onStop() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7301) {
            val pending = pendingMonitor; pendingMonitor = null
            if (pending != null && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                try { ActivationMonitorService.start(this, pending["token"] as String, pending["apiUrl"] as String, pending["expiresAt"] as Long) }
                catch (_: Exception) { /* Reopening the app allows another foreground start attempt. */ }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeNotification()?.let { deviceChannel?.invokeMethod("activationNotificationTapped", it) }
    }

    private fun consumeNotification(): Map<String, Any>? {
        if (!intent.getBooleanExtra("activation_notification", false)) return null
        val details = mapOf<String, Any>(
            "status" to (intent.getStringExtra("activation_status") ?: "Pending"),
            "productId" to intent.getIntExtra("activation_product_id", -1),
            "productCode" to (intent.getStringExtra("activation_product_code") ?: "")
        )
        intent.removeExtra("activation_notification")
        intent.removeExtra("activation_status")
        intent.removeExtra("activation_product_id")
        intent.removeExtra("activation_product_code")
        return details
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dharmaj/device")
        deviceChannel?.setMethodCallHandler { call, result ->
                if (call.method == "androidId") {
                    result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                } else if (call.method == "requestNotificationPermission") {
                    if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7301)
                        result.success(false)
                    }
                } else if (call.method == "startRequestMonitor") {
                    try {
                        val token = call.argument<String>("token") ?: ""
                        val url = call.argument<String>("apiUrl") ?: ""
                        val expires = call.argument<Number>("expiresAt")?.toLong() ?: 0
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            pendingMonitor = mapOf("token" to token, "apiUrl" to url, "expiresAt" to expires)
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7301)
                            result.success(false)
                        } else {
                            ActivationMonitorService.start(this, token, url, expires)
                            result.success(true)
                        }
                    } catch (_: Exception) { result.error("MONITOR_UNAVAILABLE", "Background alerts could not start. Reopen the app and try again.", null) }
                } else if (call.method == "stopRequestMonitor") {
                    pendingMonitor = null
                    ActivationMonitorService.stop(this)
                    result.success(null)
                } else if (call.method == "showActivationNotification") {
                    showActivationNotification(
                        call.argument<String>("title") ?: "Activation update",
                        call.argument<String>("body") ?: "Your activation request has been updated.",
                        call.argument<String>("status") ?: "Pending",
                        call.argument<Number>("productId")?.toInt(),
                        call.argument<String>("productCode") ?: ""
                    )
                    result.success(null)
                } else if (call.method == "getActivationNotification") {
                    result.success(consumeNotification())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun showActivationNotification(title: String, body: String, status: String, productId: Int?, productCode: String) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel("activation_status", "Activation status", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("activation_notification", true)
            putExtra("activation_status", status)
            putExtra("activation_product_id", productId ?: -1)
            putExtra("activation_product_code", productCode)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, productId ?: 7302, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, "activation_status")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(productId ?: 7303, notification)
    }
}
