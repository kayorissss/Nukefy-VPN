package com.nukefy.vpn

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: toggles the VPN without opening the app when possible. */
class NukefyTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val running = NukefyVpnService.running
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Nukefy VPN"
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = if (running) NukefyVpnService.serverName.ifBlank { "Подключено" } else "Выключено"
        }
        tile.updateTile()
    }

    override fun onClick() {
        if (NukefyVpnService.running) {
            NukefyVpnService.requestStop(this)
            qsTile?.let {
                it.state = Tile.STATE_INACTIVE
                it.updateTile()
            }
            return
        }
        val canStartSilently = NukefyCore.hasLibbox &&
            VpnService.prepare(this) == null &&
            NukefyVpnService.hasSavedSession(this)
        if (canStartSilently) {
            NukefyVpnService.requestResume(this)
            qsTile?.let {
                it.state = Tile.STATE_ACTIVE
                it.updateTile()
            }
            return
        }
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_ACTION, "connect")
        val pending = PendingIntent.getActivity(
            this,
            7,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
