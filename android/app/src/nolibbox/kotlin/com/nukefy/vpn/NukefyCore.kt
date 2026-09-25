package com.nukefy.vpn

object NukefyCore {
    const val hasLibbox: Boolean = false

    fun version(): String? = null

    fun start(service: NukefyVpnService, configJson: String): String = "LIBBOX_MISSING"

    fun stop() {}
}
