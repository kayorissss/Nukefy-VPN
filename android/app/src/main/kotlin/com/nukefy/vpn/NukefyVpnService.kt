package com.nukefy.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.service.quicksettings.TileService
import androidx.core.app.NotificationCompat
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.concurrent.thread

class NukefyVpnService : VpnService() {
    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        when (intent?.action) {
            ACTION_STOP -> {
                stopCore()
                finish(mapOf("ok" to true, "mode" to "stopped"))
                demote()
                return START_NOT_STICKY
            }
            ACTION_PING -> {
                if (running) {
                    promoteForeground(pinging = true)
                    measurePing()
                }
                return START_STICKY
            }
            ACTION_START -> {
                promoteForeground()
                val configJson = intent.getStringExtra("configJson").orEmpty()
                val configPath = intent.getStringExtra("configPath").orEmpty()
                val preferTun = intent.getBooleanExtra("preferTun", false)
                serverName = intent.getStringExtra("serverName").orEmpty()
                serverHost = intent.getStringExtra("serverHost").orEmpty()
                serverPort = intent.getIntExtra("serverPort", 0)
                lastPing = null
                val error = startCore(configJson, configPath, preferTun)
                if (error != null) {
                    stopCore()
                    finish(mapOf("ok" to false, "mode" to mode, "error" to error))
                    demote()
                    return START_NOT_STICKY
                }
                running = true
                rememberSession(configJson, configPath)
                promoteForeground()
                requestTileUpdate()
                finish(mapOf("ok" to true, "mode" to mode))
                return START_STICKY
            }
            else -> {
                // Revive after process death / boot, or start from the quick tile.
                promoteForeground()
                val session = readSession()
                if (session != null && (intent?.action == ACTION_RESUME || shouldRevive())) {
                    val error = startCore(session.first, session.second, NukefyCore.hasLibbox)
                    if (error == null) {
                        running = true
                        promoteForeground()
                        requestTileUpdate()
                        return START_STICKY
                    }
                }
                demote()
                return START_NOT_STICKY
            }
        }
    }

    override fun onRevoke() {
        stopCore()
        demote()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopCore()
        super.onDestroy()
    }

    private fun startCore(configJson: String, configPath: String, preferTun: Boolean): String? {
        if (NukefyCore.hasLibbox) {
            mode = if (preferTun) "tun" else "proxy"
            return NukefyCore.start(this, configJson)
        }
        // Android 10+ forbids executing binaries from app data (W^X), so a
        // downloaded sing-box cannot run here. Without libbox we refuse early
        // with a stable code the UI can explain instead of an EACCES trace.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            mode = "missing"
            return "LIBBOX_MISSING"
        }
        val binary = binaryFile(this)
        if (binary == null || !binary.exists()) {
            mode = "missing"
            return "CORE_MISSING"
        }
        mode = "proxy"
        return startProcess(binary, configPath)
    }

    private fun startProcess(binary: File, configPath: String): String? {
        return try {
            val work = File(configPath).parentFile ?: filesDir
            val proc = ProcessBuilder(binary.absolutePath, "run", "-c", configPath, "-D", work.absolutePath)
                .directory(binary.parentFile)
                .redirectErrorStream(true)
                .start()
            process = proc
            Thread.sleep(700)
            if (!alive(proc)) {
                val log = proc.inputStream.bufferedReader().use { it.readText() }.trim()
                process = null
                if (log.isEmpty()) "core-exited" else log.take(800)
            } else {
                null
            }
        } catch (error: Exception) {
            process = null
            error.message ?: "exec-failed"
        }
    }

    private fun stopCore() {
        running = false
        NukefyCore.stop()
        process?.destroy()
        process = null
        requestTileUpdate()
    }

    private fun finish(payload: Map<String, Any?>) {
        val callback = pending
        pending = null
        callback?.invoke(payload)
    }

    private fun demote() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, "Nukefy VPN", NotificationManager.IMPORTANCE_LOW)
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    private fun promoteForeground(pinging: Boolean = false) {
        val notification = notification(pinging)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun notification(pinging: Boolean): Notification {
        val open = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            2,
            Intent(this, NukefyVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val ping = PendingIntent.getService(
            this,
            3,
            Intent(this, NukefyVpnService::class.java).setAction(ACTION_PING),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = if (serverName.isNotBlank()) serverName else "Nukefy VPN"
        val text = when {
            !running -> "Подключение…"
            pinging -> "Проверяем пинг…"
            lastPing != null && lastPing!! >= 0 -> "Подключено · пинг ${lastPing} мс"
            lastPing != null -> "Подключено · сервер не ответил"
            else -> "Подключено"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setColor(0xFF00E5FF.toInt())
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, "Пинг", ping)
            .addAction(0, "Отключить", stop)
            .build()
    }

    private fun measurePing() {
        val host = serverHost
        val port = serverPort
        thread(name = "nukefy-ping") {
            val result = if (host.isBlank() || port <= 0) {
                -1
            } else {
                try {
                    val start = System.nanoTime()
                    Socket().use { socket ->
                        protect(socket)
                        socket.connect(InetSocketAddress(host, port), 4000)
                    }
                    ((System.nanoTime() - start) / 1_000_000L).toInt()
                } catch (_: Exception) {
                    -1
                }
            }
            lastPing = result
            if (running) {
                getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification(false))
            }
        }
    }

    private fun rememberSession(configJson: String, configPath: String) {
        try {
            val dir = File(filesDir, "run").apply { mkdirs() }
            File(dir, "last_config.json").writeText(configJson)
            File(dir, "last_meta.txt").writeText("$configPath\n$serverName\n$serverHost\n$serverPort")
        } catch (_: Exception) {
        }
    }

    private fun readSession(): Pair<String, String>? {
        val dir = File(filesDir, "run")
        val config = File(dir, "last_config.json")
        if (!config.exists()) return null
        val meta = File(dir, "last_meta.txt").takeIf { it.exists() }?.readLines().orEmpty()
        serverName = meta.getOrNull(1).orEmpty()
        serverHost = meta.getOrNull(2).orEmpty()
        serverPort = meta.getOrNull(3)?.toIntOrNull() ?: 0
        return config.readText() to (meta.getOrNull(0) ?: config.absolutePath)
    }

    private fun requestTileUpdate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                TileService.requestListeningState(
                    this,
                    android.content.ComponentName(this, NukefyTileService::class.java),
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun shouldRevive(): Boolean {
        val prefs = getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE)
        if (prefs.getBoolean("auto_connect", false)) return true
        val flags = File(filesDir, "boot_flags.json")
        if (!flags.exists()) return false
        return flags.readText().contains("\"autoConnect\":true")
    }

    companion object {
        const val ACTION_START = "com.nukefy.vpn.START"
        const val ACTION_STOP = "com.nukefy.vpn.STOP"
        const val ACTION_PING = "com.nukefy.vpn.PING"
        const val ACTION_RESUME = "com.nukefy.vpn.RESUME"
        private const val CHANNEL_ID = "nukefy_vpn"
        private const val NOTIF_ID = 42

        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        var serverName: String = ""
            private set

        private var serverHost: String = ""
        private var serverPort: Int = 0
        private var lastPing: Int? = null
        private var mode: String = "missing"
        private var process: Process? = null
        private var pending: ((Map<String, Any?>) -> Unit)? = null

        fun hasSavedSession(context: Context): Boolean =
            File(context.filesDir, "run/last_config.json").exists()

        fun requestStart(
            context: Context,
            configPath: String,
            configJson: String,
            preferTun: Boolean,
            serverName: String,
            serverHost: String,
            serverPort: Int,
            callback: (Map<String, Any?>) -> Unit,
        ) {
            pending = callback
            val intent = Intent(context, NukefyVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra("configPath", configPath)
                .putExtra("configJson", configJson)
                .putExtra("preferTun", preferTun)
                .putExtra("serverName", serverName)
                .putExtra("serverHost", serverHost)
                .putExtra("serverPort", serverPort)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun requestResume(context: Context) {
            val intent = Intent(context, NukefyVpnService::class.java).setAction(ACTION_RESUME)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun requestStop(context: Context) {
            val intent = Intent(context, NukefyVpnService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }

        fun coreInfo(context: Context): Map<String, Any?> {
            val binary = binaryFile(context)
            return mapOf(
                "libbox" to NukefyCore.hasLibbox,
                "binary" to (binary?.exists() == true),
                "binaryPath" to binary?.absolutePath,
                "version" to NukefyCore.version(),
                "running" to running,
            )
        }

        fun binaryFile(context: Context): File? {
            val stored = context.getSharedPreferences(MainActivity.PREFS, MODE_PRIVATE)
                .getString(MainActivity.KEY_BINARY, null)
            if (!stored.isNullOrEmpty()) return File(stored)
            val candidate = File(context.filesDir, "core/sing-box")
            return if (candidate.exists()) candidate else null
        }

        fun alive(proc: Process): Boolean {
            return try {
                proc.exitValue()
                false
            } catch (_: IllegalThreadStateException) {
                true
            }
        }
    }
}
