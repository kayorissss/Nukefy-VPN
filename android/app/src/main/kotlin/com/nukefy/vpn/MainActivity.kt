package com.nukefy.vpn

import android.app.Activity
import android.app.StatusBarManager
import android.content.ComponentName
import android.graphics.drawable.Icon
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var vpnResult: MethodChannel.Result? = null
    private var launchAction: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        launchAction = intent?.getStringExtra(EXTRA_ACTION)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchAction = intent.getStringExtra(EXTRA_ACTION) ?: launchAction
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "coreInfo" -> result.success(NukefyVpnService.coreInfo(this))
                    "start" -> {
                        val configPath = call.argument<String>("configPath") ?: ""
                        val configJson = call.argument<String>("configJson") ?: ""
                        val preferTun = call.argument<Boolean>("preferTun") ?: false
                        val serverName = call.argument<String>("serverName") ?: ""
                        val serverHost = call.argument<String>("serverHost") ?: ""
                        val serverPort = call.argument<Int>("serverPort") ?: 0
                        NukefyVpnService.requestStart(
                            this, configPath, configJson, preferTun, serverName, serverHost, serverPort,
                        ) { payload ->
                            runOnUiThread { result.success(payload) }
                        }
                    }
                    "stop" -> {
                        NukefyVpnService.requestStop(this)
                        result.success(null)
                    }
                    "status" -> result.success(mapOf("running" to NukefyVpnService.running))
                    "prepareVpn" -> prepareVpn(result)
                    "listApps" -> result.success(listApps())
                    "setAutoStart" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        getSharedPreferences(PREFS, MODE_PRIVATE)
                            .edit()
                            .putBoolean(KEY_AUTOSTART, enabled)
                            .apply()
                        result.success(null)
                    }
                    "requestAddTile" -> requestAddTile(result)
                    "openVpnSettings" -> {
                        startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "requestBatteryOptimization" -> {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                            .setData(Uri.parse("package:$packageName"))
                        startActivity(intent)
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        result.success(if (path == null) false else installApk(path))
                    }
                    "registerBinary" -> {
                        val path = call.argument<String>("path")
                        getSharedPreferences(PREFS, MODE_PRIVATE)
                            .edit()
                            .putString(KEY_BINARY, path)
                            .apply()
                        result.success(null)
                    }
                    "consumeLaunchAction" -> {
                        val action = launchAction
                        launchAction = null
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        vpnResult = result
        startActivityForResult(intent, REQ_VPN)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            vpnResult?.success(resultCode == Activity.RESULT_OK)
            vpnResult = null
        }
    }

    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        return pm.getInstalledApplications(0).map { info ->
            mapOf(
                "package" to info.packageName,
                "label" to pm.getApplicationLabel(info).toString(),
                "system" to ((info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0),
            )
        }.sortedBy { it["label"] as String }
    }

    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Asks Android 13+ to add the VPN tile to Quick Settings. Older systems return "unsupported". */
    private fun requestAddTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("unsupported")
            return
        }
        try {
            val manager = getSystemService(StatusBarManager::class.java)
            manager.requestAddTileService(
                ComponentName(this, NukefyTileService::class.java),
                "Nukefy VPN",
                Icon.createWithResource(this, R.drawable.ic_stat_vpn),
                mainExecutor,
            ) { code -> runOnUiThread { result.success(code.toString()) } }
        } catch (error: Exception) {
            result.success("error:${error.message}")
        }
    }

    companion object {
        const val CHANNEL = "com.nukefy.vpn/core"
        const val EXTRA_ACTION = "nukefy_action"
        const val PREFS = "nukefy_native"
        const val KEY_AUTOSTART = "autostart"
        const val KEY_BINARY = "binary"
        private const val REQ_VPN = 4101
    }
}
