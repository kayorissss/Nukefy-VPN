package com.nukefy.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.ProxyInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InterfaceAddress
import java.util.Enumeration
import io.nekohasekai.libbox.NetworkInterface as LibboxInterface

/**
 * Typed bridge to sing-box `libbox` (built from the v1.12 line, see
 * `tool/build_libbox.sh` and `.github/workflows/release.yml`).
 *
 * This source set is compiled only when `android/app/libs/libbox.aar` exists;
 * otherwise `src/nolibbox` provides a stub with `hasLibbox = false`.
 */
object NukefyCore {
    const val hasLibbox: Boolean = true

    private var box: BoxService? = null
    private var tun: ParcelFileDescriptor? = null
    private var platform: Platform? = null
    private var setupDone = false

    fun version(): String? = try {
        Libbox.version()
    } catch (error: Throwable) {
        Log.w(TAG, "version", error)
        null
    }

    /** Returns `null` on success or a human readable error. */
    fun start(service: NukefyVpnService, configJson: String): String? {
        stop()
        return try {
            setup(service)
            val platform = Platform(service)
            this.platform = platform
            val created = Libbox.newService(configJson, platform)
            created.start()
            box = created
            null
        } catch (error: Throwable) {
            Log.e(TAG, "start", error)
            stop()
            error.message ?: error.toString()
        }
    }

    fun stop() {
        val current = box
        box = null
        if (current != null) {
            try {
                current.close()
            } catch (error: Throwable) {
                Log.w(TAG, "close", error)
            }
        }
        platform?.release()
        platform = null
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun setup(context: Context) {
        if (setupDone) return
        val base = context.filesDir.absolutePath
        val options = SetupOptions()
        options.basePath = base
        options.workingPath = "$base/run"
        options.tempPath = context.cacheDir.absolutePath
        options.fixAndroidStack = true
        Libbox.setup(options)
        try {
            Libbox.setLocale("ru")
        } catch (_: Throwable) {
        }
        setupDone = true
    }

    // ------------------------------------------------------------------ //

    private class Platform(private val service: NukefyVpnService) : PlatformInterface {
        private val connectivity =
            service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        private val handler = Handler(Looper.getMainLooper())
        private var networkCallback: ConnectivityManager.NetworkCallback? = null
        private var interfaceListener: InterfaceUpdateListener? = null

        fun release() {
            closeMonitor()
        }

        override fun localDNSTransport(): LocalDNSTransport? = null

        override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

        override fun autoDetectInterfaceControl(fd: Int) {
            if (!service.protect(fd)) {
                Log.w(TAG, "protect($fd) failed")
            }
        }

        override fun openTun(options: TunOptions): Int {
            if (android.net.VpnService.prepare(service) != null) {
                error("VPN permission is missing")
            }
            val builder = service.Builder()
                .setSession("Nukefy VPN")
                .setMtu(options.getMTU())

            var addresses = 0
            options.getInet4Address().forEach { addr, prefix ->
                builder.addAddress(addr, prefix)
                addresses++
            }
            options.getInet6Address().forEach { addr, prefix ->
                builder.addAddress(addr, prefix)
                addresses++
            }
            if (addresses == 0) {
                builder.addAddress("172.19.0.1", 30)
            }

            if (options.getAutoRoute()) {
                val dns = try {
                    options.getDNSServerAddress()?.getValue()
                } catch (_: Throwable) {
                    null
                }
                builder.addDnsServer(dns?.takeIf { it.isNotBlank() } ?: "172.19.0.2")

                if (Build.VERSION.SDK_INT >= 33) {
                    var v4 = 0
                    options.getInet4RouteAddress().forEach { addr, prefix ->
                        builder.addRoute(addr, prefix)
                        v4++
                    }
                    if (v4 == 0) builder.addRoute("0.0.0.0", 0)
                    var v6 = 0
                    options.getInet6RouteAddress().forEach { addr, prefix ->
                        builder.addRoute(addr, prefix)
                        v6++
                    }
                    if (v6 == 0) builder.addRoute("::", 0)
                    options.getInet4RouteExcludeAddress().forEach { addr, prefix ->
                        builder.excludeRoute(IpPrefix(InetAddress.getByName(addr), prefix))
                    }
                    options.getInet6RouteExcludeAddress().forEach { addr, prefix ->
                        builder.excludeRoute(IpPrefix(InetAddress.getByName(addr), prefix))
                    }
                } else {
                    var v4 = 0
                    options.getInet4RouteRange().forEach { addr, prefix ->
                        builder.addRoute(addr, prefix)
                        v4++
                    }
                    if (v4 == 0) builder.addRoute("0.0.0.0", 0)
                    var v6 = 0
                    options.getInet6RouteRange().forEach { addr, prefix ->
                        builder.addRoute(addr, prefix)
                        v6++
                    }
                    if (v6 == 0) builder.addRoute("::", 0)
                }

                val include = options.getIncludePackage().toList()
                val exclude = options.getExcludePackage().toList()
                if (include.isNotEmpty()) {
                    for (pkg in include) {
                        try {
                            builder.addAllowedApplication(pkg)
                        } catch (_: Exception) {
                        }
                    }
                } else {
                    for (pkg in exclude) {
                        try {
                            builder.addDisallowedApplication(pkg)
                        } catch (_: Exception) {
                        }
                    }
                }
            }

            if (options.isHTTPProxyEnabled() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val bypass = options.getHTTPProxyBypassDomain().toList()
                builder.setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        options.getHTTPProxyServer(),
                        options.getHTTPProxyServerPort(),
                        bypass,
                    ),
                )
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            val pfd = builder.establish() ?: error("VPN establish() returned null")
            tun = pfd
            return pfd.fd
        }

        override fun writeLog(message: String?) {
            Log.i(TAG, message ?: "")
        }

        override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

        override fun findConnectionOwner(
            ipProtocol: Int,
            sourceAddress: String,
            sourcePort: Int,
            destinationAddress: String,
            destinationPort: Int,
        ): Int {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) error("unsupported")
            val uid = connectivity.getConnectionOwnerUid(
                ipProtocol,
                java.net.InetSocketAddress(sourceAddress, sourcePort),
                java.net.InetSocketAddress(destinationAddress, destinationPort),
            )
            if (uid == android.os.Process.INVALID_UID) error("connection owner not found")
            return uid
        }

        override fun packageNameByUid(uid: Int): String {
            val packages = service.packageManager.getPackagesForUid(uid)
            if (packages.isNullOrEmpty()) error("unknown uid $uid")
            return packages[0]
        }

        override fun uidByPackageName(packageName: String): Int {
            return try {
                if (Build.VERSION.SDK_INT >= 33) {
                    service.packageManager.getPackageUid(
                        packageName,
                        android.content.pm.PackageManager.PackageInfoFlags.of(0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    service.packageManager.getPackageUid(packageName, 0)
                }
            } catch (error: Exception) {
                error("package not found: $packageName")
            }
        }

        override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
            closeMonitor()
            interfaceListener = listener
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                .build()
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = publish(network)
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                    publish(network)

                override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) =
                    publish(network)

                override fun onLost(network: Network) {
                    interfaceListener?.updateDefaultInterface("", -1, false, false)
                }
            }
            networkCallback = callback
            try {
                if (Build.VERSION.SDK_INT >= 31) {
                    connectivity.registerBestMatchingNetworkCallback(request, callback, handler)
                } else if (Build.VERSION.SDK_INT >= 28) {
                    connectivity.requestNetwork(request, callback, handler)
                } else {
                    connectivity.requestNetwork(request, callback)
                }
            } catch (error: Exception) {
                Log.w(TAG, "network callback", error)
            }
            connectivity.activeNetwork?.let { publish(it) }
        }

        private fun publish(network: Network) {
            val listener = interfaceListener ?: return
            val props = connectivity.getLinkProperties(network) ?: return
            val name = props.interfaceName ?: return
            val index = try {
                java.net.NetworkInterface.getByName(name)?.index ?: return
            } catch (_: Exception) {
                return
            }
            val caps = connectivity.getNetworkCapabilities(network)
            val expensive = caps != null &&
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            listener.updateDefaultInterface(name, index, expensive, false)
        }

        override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
            closeMonitor()
        }

        private fun closeMonitor() {
            val callback = networkCallback ?: return
            networkCallback = null
            interfaceListener = null
            try {
                connectivity.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }

        override fun getInterfaces(): NetworkInterfaceIterator {
            val list = ArrayList<LibboxInterface>()
            val enumeration: Enumeration<java.net.NetworkInterface>? = try {
                java.net.NetworkInterface.getNetworkInterfaces()
            } catch (_: Exception) {
                null
            }
            enumeration?.let { all ->
                for (iface in all) {
                    val item = LibboxInterface()
                    item.setName(iface.name)
                    item.setIndex(iface.index)
                    item.setMTU(try { iface.mtu } catch (_: Exception) { 1500 })
                    item.setAddresses(StringList(iface.interfaceAddresses.map(::prefixOf)))
                    item.setFlags(flagsOf(iface))
                    item.setType(typeOf(iface.name))
                    item.setDNSServer(StringList(emptyList()))
                    item.setMetered(false)
                    list.add(item)
                }
            }
            return InterfaceList(list)
        }

        override fun underNetworkExtension(): Boolean = false

        override fun includeAllNetworks(): Boolean = false

        override fun readWIFIState(): WIFIState? = null

        override fun systemCertificates(): StringIterator = StringList(emptyList())

        override fun clearDNSCache() {}

        override fun sendNotification(notification: Notification?) {}

        private fun typeOf(name: String): Int = when {
            name.startsWith("wlan") || name.startsWith("wifi") -> Libbox.InterfaceTypeWIFI
            name.startsWith("rmnet") || name.startsWith("ccmni") || name.startsWith("pdp") -> Libbox.InterfaceTypeCellular
            name.startsWith("eth") -> Libbox.InterfaceTypeEthernet
            else -> Libbox.InterfaceTypeOther
        }

        private fun flagsOf(iface: java.net.NetworkInterface): Int {
            var flags = 0
            try {
                if (iface.isUp) flags = flags or 0x1 or 0x40 // IFF_UP | IFF_RUNNING
                if (iface.isLoopback) flags = flags or 0x8
                if (iface.isPointToPoint) flags = flags or 0x10
                if (iface.supportsMulticast()) flags = flags or 0x1000
                if (!iface.isLoopback && !iface.isPointToPoint) flags = flags or 0x2 // IFF_BROADCAST
            } catch (_: Exception) {
            }
            return flags
        }

        private fun prefixOf(address: InterfaceAddress): String {
            val inet = address.address
            val host = if (inet is Inet6Address) {
                inet.hostAddress?.substringBefore('%') ?: "::"
            } else {
                inet.hostAddress ?: "0.0.0.0"
            }
            return "$host/${address.networkPrefixLength}"
        }
    }

    private class StringList(private val values: List<String>) : StringIterator {
        private var index = 0
        override fun len(): Int = values.size
        override fun hasNext(): Boolean = index < values.size
        override fun next(): String = values[index++]
    }

    private class InterfaceList(private val values: List<LibboxInterface>) : NetworkInterfaceIterator {
        private var index = 0
        override fun hasNext(): Boolean = index < values.size
        override fun next(): LibboxInterface = values[index++]
    }

    private inline fun io.nekohasekai.libbox.RoutePrefixIterator.forEach(block: (String, Int) -> Unit) {
        while (hasNext()) {
            val prefix = next()
            block(prefix.address(), prefix.prefix())
        }
    }

    private fun StringIterator.toList(): List<String> {
        val out = ArrayList<String>()
        while (hasNext()) out.add(next())
        return out
    }

    private const val TAG = "NukefyCore"
}
