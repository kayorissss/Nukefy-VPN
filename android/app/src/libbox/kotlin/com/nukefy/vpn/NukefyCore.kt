package com.nukefy.vpn

import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.lang.reflect.InvocationHandler
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.net.InetAddress

/**
 * Runtime bridge for a sing-box 1.12 `libbox.aar`.
 * Method names are resolved by reflection so a small API drift does not
 * require a rewrite, as long as `Libbox.setup` / `Libbox.newService` exist.
 */
object NukefyCore {
    const val hasLibbox: Boolean = true

    private var box: Any? = null
    private var tun: ParcelFileDescriptor? = null

    fun version(): String? {
        return try {
            Class.forName("io.nekohasekai.libbox.Libbox")
                .getMethod("version")
                .invoke(null) as? String
        } catch (error: Throwable) {
            Log.w(TAG, "version", error)
            null
        }
    }

    fun start(service: NukefyVpnService, configJson: String): String? {
        stop()
        return try {
            setup(service)
            val libbox = Class.forName("io.nekohasekai.libbox.Libbox")
            val iface = Class.forName("io.nekohasekai.libbox.PlatformInterface")
            val platform = Proxy.newProxyInstance(
                iface.classLoader,
                arrayOf(iface),
                PlatformHandler(service),
            )
            val factory = libbox.methods.first { it.name == "newService" && it.parameterTypes.size == 2 }
            val created = factory.invoke(null, configJson, platform)
            created.javaClass.getMethod("start").invoke(created)
            box = created
            null
        } catch (error: Throwable) {
            val cause = (error as? InvocationTargetException)?.targetException ?: error
            Log.e(TAG, "start", cause)
            stop()
            cause.message ?: cause.toString()
        }
    }

    fun stop() {
        val current = box
        box = null
        if (current != null) {
            try {
                current.javaClass.getMethod("close").invoke(current)
            } catch (error: Throwable) {
                Log.w(TAG, "close", error)
            }
        }
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun setup(service: NukefyVpnService) {
        val libbox = Class.forName("io.nekohasekai.libbox.Libbox")
        val optionsClass = Class.forName("io.nekohasekai.libbox.SetupOptions")
        val options = optionsClass.getDeclaredConstructor().newInstance()
        val base = service.filesDir.absolutePath
        set(options, "basePath", base)
        set(options, "workingPath", "$base/run")
        set(options, "tempPath", service.cacheDir.absolutePath)
        set(options, "fixAndroidStack", true)
        libbox.getMethod("setup", optionsClass).invoke(null, options)
    }

    private fun set(target: Any, name: String, value: Any?) {
        val field = target.javaClass.fields.firstOrNull { it.name.equals(name, true) }
            ?: target.javaClass.declaredFields.firstOrNull { it.name.equals(name, true) }
        if (field != null) {
            field.isAccessible = true
            field.set(target, value)
            return
        }
        val setter = target.javaClass.methods.firstOrNull {
            it.name.equals("set${name.replaceFirstChar { c -> c.uppercase() }}", true) && it.parameterTypes.size == 1
        }
        setter?.invoke(target, value)
    }

    private class PlatformHandler(private val service: NukefyVpnService) : InvocationHandler {
        override fun invoke(proxy: Any, method: Method, args: Array<out Any>?): Any? {
            val name = method.name
            return try {
                when (name) {
                    "openTun" -> openTun(args?.firstOrNull())
                    "usePlatformAutoDetectInterfaceControl" -> true
                    "autoDetectInterfaceControl" -> {
                        val fd = (args?.firstOrNull() as? Number)?.toInt() ?: return null
                        service.protect(fd)
                        null
                    }
                    "useProcFS" -> Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
                    "underNetworkExtension", "includeAllNetworks" -> false
                    "writeLog" -> {
                        Log.i(TAG, args?.firstOrNull()?.toString() ?: "")
                        null
                    }
                    "localDNSTransport" -> stub("io.nekohasekai.libbox.LocalDNSTransport")
                    "systemCertificates", "getInterfaces" -> emptyIterator()
                    "findConnectionOwner", "packageNameByUid", "uIDByPackageName" -> defaultReturn(method.returnType)
                    else -> defaultReturn(method.returnType)
                }
            } catch (error: Throwable) {
                Log.e(TAG, name, error)
                if (name == "openTun") throw error
                defaultReturn(method.returnType)
            }
        }

        private fun openTun(options: Any?): Int {
            val builder = service.Builder()
            builder.setSession("Nukefy VPN")
            builder.setMtu(intProp(options, "getMTU", "mtu") ?: 9000)
            val added = addPrefixes(builder, options, "getInet4Address") +
                addPrefixes(builder, options, "getInet6Address")
            if (added == 0) {
                builder.addAddress("172.19.0.1", 30)
                builder.addRoute("0.0.0.0", 0)
            }
            builder.addDnsServer("172.19.0.2")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            val include = strings(options, "getIncludePackage")
            val exclude = strings(options, "getExcludePackage")
            if (include.isNotEmpty()) {
                for (pkg in include) {
                    try {
                        builder.addAllowedApplication(pkg)
                    } catch (_: Exception) {
                    }
                }
            } else {
                try {
                    builder.addDisallowedApplication(service.packageName)
                } catch (_: Exception) {
                }
                for (pkg in exclude) {
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (_: Exception) {
                    }
                }
            }
            val pfd = builder.establish() ?: error("VPN establish() returned null")
            tun = pfd
            return pfd.fd
        }
    }

    private fun addPrefixes(builder: VpnService.Builder, options: Any?, method: String): Int {
        val iterator = call(options, method) ?: return 0
        var count = 0
        while (boolProp(iterator, "hasNext")) {
            val prefix = call(iterator, "next") ?: break
            val address = call(prefix, "address")?.toString() ?: call(prefix, "getAddress")?.toString() ?: continue
            val bits = intProp(prefix, "prefix", "getPrefix") ?: 32
            val inet = InetAddress.getByName(address.substringBefore("/"))
            if (inet.address.size == 4) {
                builder.addAddress(inet, bits)
                builder.addRoute("0.0.0.0", 0)
            } else {
                builder.addAddress(inet, bits)
                builder.addRoute("::", 0)
            }
            count++
        }
        return count
    }

    private fun strings(options: Any?, method: String): List<String> {
        val iterator = call(options, method) ?: return emptyList()
        val values = mutableListOf<String>()
        while (boolProp(iterator, "hasNext")) {
            val next = call(iterator, "next") ?: break
            values.add(next.toString())
        }
        return values
    }

    private fun call(target: Any?, name: String): Any? {
        if (target == null) return null
        val method = target.javaClass.methods.firstOrNull { it.name == name && it.parameterTypes.isEmpty() }
            ?: return null
        return method.invoke(target)
    }

    private fun intProp(target: Any?, vararg names: String): Int? {
        for (name in names) {
            val value = call(target, name)
            if (value is Number) return value.toInt()
        }
        return null
    }

    private fun boolProp(target: Any?, name: String): Boolean {
        return call(target, name) == true
    }

    private fun emptyIterator(): Any? = stub("io.nekohasekai.libbox.StringIterator")

    private fun stub(className: String): Any? {
        return try {
            val type = Class.forName(className)
            Proxy.newProxyInstance(type.classLoader, arrayOf(type)) { _, method, _ ->
                defaultReturn(method.returnType)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun defaultReturn(type: Class<*>): Any? {
        return when (type) {
            java.lang.Boolean.TYPE, java.lang.Boolean::class.java -> false
            java.lang.Integer.TYPE, Integer::class.java -> 0
            java.lang.Long.TYPE, java.lang.Long::class.java -> 0L
            java.lang.Void.TYPE, Void.TYPE -> null
            else -> null
        }
    }

    private const val TAG = "NukefyCore"
}
