package com.nukefy.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.io.File

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }
        if (!launchOnBoot(context)) return
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(MainActivity.EXTRA_ACTION, if (autoConnect(context)) "connect" else "show")
        try {
            context.startActivity(launch)
        } catch (_: Exception) {
            notify(context, launch)
        }
    }

    private fun notify(context: Context, launch: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel("nukefy_vpn", "Nukefy VPN", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        val pending = PendingIntent.getActivity(
            context,
            9,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, "nukefy_vpn")
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentTitle("Nukefy VPN")
            .setContentText("Tap to open")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(9, notification)
    }

    private fun launchOnBoot(context: Context): Boolean {
        val native = context.getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)
        if (native.getBoolean(MainActivity.KEY_AUTOSTART, false)) return true
        val flutter = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (flutter.getBoolean("flutter.launch_on_boot", false)) return true
        if (flutter.getBoolean("flutter.flutter.launch_on_boot", false)) return true
        return readFlag(context, "launchOnBoot")
    }

    private fun autoConnect(context: Context): Boolean {
        val flutter = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (flutter.getBoolean("flutter.auto_connect", false)) return true
        if (flutter.getBoolean("flutter.flutter.auto_connect", false)) return true
        return readFlag(context, "autoConnect")
    }

    private fun readFlag(context: Context, key: String): Boolean {
        val file = File(context.filesDir, "boot_flags.json")
        if (!file.exists()) return false
        return file.readText().contains("\"$key\":true")
    }
}
